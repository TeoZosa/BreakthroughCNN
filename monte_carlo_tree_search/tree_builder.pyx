#cython: language_level=3, boundscheck=False

from Breakthrough_Player.board_utils import enumerate_legal_moves_using_piece_arrays, move_piece_update_piece_arrays
from tools.utils import index_lookup_by_move, move_lookup_by_index
from monte_carlo_tree_search.TreeNode import TreeNode
from Breakthrough_Player.board_utils import  check_legality_MCTS, get_top_children
from monte_carlo_tree_search.tree_search_utils import update_tree_losses, update_tree_wins, \
    update_child, update_win_status_from_children, eval_child, eval_children, SimulationInfo, backpropagate_num_checked_children, \
    increment_threads_checking_node, decrement_threads_checking_node, reset_threads_checking_node, get_opponent_color, update_num_children_being_checked
from multiprocessing import Pool, Process, pool
# from math import ceil
from threading import Lock, current_thread
from sys import stdout
from time import time
cimport numpy as np

class NoDaemonProcess(Process):
    # make 'daemon' attribute always return False
    def _get_daemon(self):
        return False
    def _set_daemon(self, value):
        pass
    daemon = property(_get_daemon, _set_daemon)

# We sub-class multiprocessing.pool.Pool instead of multiprocessing.Pool
# because the latter is only a wrapper function, not a proper class.
class MyPool(pool.Pool):  # Had to make a special class to allow for an inner process pool
    Process = NoDaemonProcess




# def build_game_tree(player_color, depth, unvisited_queue, depth_limit): #first-pass BFS to enumerate all the concrete nodes we want to keep track of/run through policy net
#     if depth < depth_limit: # play game at this root to depth limit
#        visited_queue = visit_to_depth_limit(player_color, depth, unvisited_queue, depth_limit)
#     else: #reached depth limit;
#        update_bottom_of_tree(unvisited_queue)
#        visited_queue = [] #don't return bottom of tree so it doesn't run inference on these nodes
#     return visited_queue
#
#
# def visit_to_depth_limit(player_color, depth, unvisited_queue, depth_limit):
#
#     unvisited_children = visit_all_nodes_and_expand_multithread(unvisited_queue, player_color)
#     visited_queue = unvisited_queue  # all queue members have now been visited
#
#     if len(unvisited_children) > 0:  # if children to visit
#         # visit children
#         opponent_color = get_opponent_color(player_color)
#         visited_queue.extend(build_game_tree(opponent_color, depth + 1, unvisited_children,
#                                              depth_limit)) #TODO: is recursion taking too long/too much stack space?
#         # else: game over taken care of in visit
#     return visited_queue
#
#
# def update_bottom_of_tree(unvisited_queue):#don't do this as it will mark the bottom as losses
#     #NN will take care of these wins.
#     for node in unvisited_queue:  # bottom of tree, so percolate visits to the top
#         random_rollout(node)
#         #don't return bottom of tree so it doesn't run inference on these nodes
#     # visited_queue = unvisited_queue
#     # return visited_queue



# def visit_all_nodes_and_expand_single_thread(unvisited_queue, player_color):
#     unvisited_children = []
#     for this_root_node in unvisited_queue:  # if empty=> nothing to visit;
#        unvisited_child_nodes= visit_single_node_and_expand([this_root_node, player_color])
#        unvisited_children.extend(unvisited_child_nodes)
#     return unvisited_children
#
# def visit_all_nodes_and_expand_multithread(unvisited_queue, player_color):
#     unvisited_children = []
#     arg_lists = [[node, player_color] for node in unvisited_queue]
#     processes = Pool(processes=7)#prevent threads from taking up too much memory before joining
#     unvisited_children_separated = processes.map(visit_single_node_and_expand, arg_lists)  # synchronized with unvisited queue
#     processes.close()
#     processes.join()
#     for i in range (0, len(unvisited_children_separated)):#does this still outweigh just single threading?
#         child_nodes = unvisited_children_separated[i]
#         parent_node = arg_lists[i][0]
#         for child in child_nodes:
#             child['parent'] =parent_node
#         parent_node['children'] =child_nodes
#         unvisited_children.extend(child_nodes)
#     return unvisited_children
#
# def visit_single_node_and_expand(node_and_color):
#     node = node_and_color[0]
#     unvisited_children = expand_node(node)
#     return unvisited_children #necessary if multiprocessing from above
#
# def visit_single_node_and_expand_no_lookahead(node_and_color):
#     node = node_and_color[0]
#     node_color = node_and_color[1]
#     unvisited_children = []
#     game_board = node['game_board']
#     is_game_over, winner_color = game_over(game_board)
#     if is_game_over:  # only useful at end of game
#         set_game_over_values(node)
#     else:  # expand node, adding children to parent
#         unvisited_children = expand_node(node)
#     return unvisited_children
#
# def expand_node(parent_node, rollout=False):
#     children_as_moves = enumerate_legal_moves_using_piece_arrays(parent_node)
#     child_nodes = []
#     children_win_statuses = []
#     for child_as_move in children_as_moves:  # generate children
#         move = child_as_move['From'] + r'-' + child_as_move['To']
#         child_node = init_unique_child_node_and_board(move, parent_node)
#         check_for_winning_move(child_node, rollout) #1-step lookahead for gameover
#         children_win_statuses.append(child_node['win_status'])
#         child_nodes.append(child_node)
#     set_win_status_from_children(parent_node, children_win_statuses)
#     if parent_node['children'] is None: #if another thread didn't expand and update thisnode
#        parent_node['children'] =child_nodes
#     return child_nodes


cpdef expand_descendants_to_depth_wrt_NN(list unexpanded_nodes, int depth, int depth_limit, dict sim_info, lock, policy_net): #nodes are all at the same depth
    # Prunes child nodes to be the NN's top predictions or instant gameovers.
    # expands all nodes at a depth to the depth limit to take advantage of GPU batch processing.
    # This step takes time away from MCTS in the beginning, but builds the tree that the MCTS will use later on in the game.
    # original_unexpanded_node.
    cdef:
        list unfiltered_unexpanded_nodes
        list filtered_unexpanded_nodes = []
        np.ndarray NN_output
        list unexpanded_children
        dict child
        dict parent

    entered_once = False
    time_to_think = sim_info['time_to_think']
    over_time = not( time() - sim_info['start_time'] < time_to_think)
    while depth < depth_limit and not over_time :# and len(sim_info['game_tree'])<10000
        entered_once = True
        # if len (unexpanded_nodes) > 0:
        #     if unexpanded_nodes[0] is None:
        #         True
        unfiltered_unexpanded_nodes = unexpanded_nodes
        if sim_info['root'] is not None:
            win_bool = sim_info['root']['win_status'] is None
        else:
            win_bool = False
        append = filtered_unexpanded_nodes.append
        if win_bool:
            # filtered_unexpanded_nodes = [node for node in unexpanded_nodes if (node['children'] is None and node['win_status'] is None)]
            for node in unexpanded_nodes:
                if node['children'] is None and node['win_status'] is None:
                    append(node)
        else: # search child even if it has a win status
            # filtered_unexpanded_nodes = [node for node in unexpanded_nodes if (node['children'] is None and not node['gameover'])]

            for node in unexpanded_nodes:
                if node['children'] is None and not node['gameover']:
                    append(node)

        if 0< len(filtered_unexpanded_nodes) < 256: #if any nodes to expand;
            if sim_info['root'] is not None: #aren't coming from reinitializing a root
                is_player = sim_info['root']['color'] == filtered_unexpanded_nodes[0]['color']
                if sim_info['main_pid'] == current_thread().name:
                    depth_limit = 1 #main thread expands once and exits to call other threads


                # elif filtered_unexpanded_nodes[0]['height'] > 50:
                #     depth_limit = 800
                # elif filtered_unexpanded_nodes[0]['height'] > 40:
                #     depth_limit = 800
                # elif filtered_unexpanded_nodes[0]['height'] > 20:
                #     depth_limit = 800

                else:
                    depth_limit = 800
            else: #initializing a new root: root is opponent node
                root = filtered_unexpanded_nodes[0]
                while root['parent'] is not None:
                    root = root['parent']
                is_player = not (root['color'] == filtered_unexpanded_nodes[0]['color'])


            depth_limit = 800

            # the point of multithreading is that other threads can do useful work while this thread blocks from the policy net calls
            # start = time()
            is_player = True
            NN_output = policy_net.evaluate(filtered_unexpanded_nodes, is_player=is_player)
            # total_time = (time()-start)*1000 # in ms
            # sim_info['eval_times'].append([len(filtered_unexpanded_nodes),total_time])

            if time_to_think >30:
                multiprocess = False
            else:
                multiprocess = False
            if multiprocess and ((len(filtered_unexpanded_nodes) >= 25 and (filtered_unexpanded_nodes[0]['color'] != sim_info['root']['color'])) or len(filtered_unexpanded_nodes) >=100):#lots of children toappend
                unexpanded_children, over_time = offload_updates_to_separate_process(filtered_unexpanded_nodes, depth, depth_limit, NN_output, sim_info, lock)
            else:
                unexpanded_children, over_time = do_updates_in_the_same_process(filtered_unexpanded_nodes, depth, depth_limit, NN_output, sim_info, lock)

            filtered_unexpanded_nodes = unexpanded_children

            depth += 1
            if not over_time and depth<depth_limit:# and len(sim_info['game_tree'])<10000
                for child in filtered_unexpanded_nodes: #set flag for children we were planning to check
                    increment_threads_checking_node(child)

        else:
            depth = depth_limit #done if no nodes to expand or too many nodes to expand
            for parent in unfiltered_unexpanded_nodes: #these nodes were from inside the function call or the unexpanded_nodes
                reset_threads_checking_node(parent)
    if not entered_once:
        for parent in unexpanded_nodes: #these nodes were from outside the function call
            decrement_threads_checking_node(parent)#

def offload_updates_to_separate_process(unexpanded_nodes,  depth, depth_limit, NN_output, sim_info, lock):
    cdef:
        int num_losing_children = 0
        list grandparents = []
        list unexpanded_children = []
        list expanded_parents
        dict parent
        dict grandparent
        int overwhelming_amount
    over_time = False
    grandparents_append = grandparents.append
    with lock:
        unchecked_nodes = []
        unchecked_append = unchecked_nodes.append

        for parent in unexpanded_nodes:
             if parent['threads_checking_node'] <= 1 and (parent['children'] is None):
                 unchecked_append(parent)
                 grandparents_append(parent['parent'])
                 parent['parent'] = None

             else:
                 decrement_threads_checking_node(parent)
        unexpanded_nodes = unchecked_nodes

    if len(unexpanded_nodes) > 0:
        # for parent in unexpanded_nodes: #moved to loop in lock
        #     grandparents.append(parent['parent'])
        #     parent['parent'] = None
        process = Pool(processes=1)
        expanded_parents, unexpanded_children, over_time = process.map(update_parents_for_process, [
            [unexpanded_nodes, NN_output, depth, depth_limit, sim_info['start_time'],
             sim_info['time_to_think'], sim_info['root']['color']]])[0]
        process.close()  # sleeps here so other threads can work
        process.join()
        with lock:
            for i in range(0, len(expanded_parents)):  # reattach these copies to tree; if adjacent parents have the same grandparent => duplicate parent in associated index in array
                parent = expanded_parents[i]
                grandparent = grandparents[i]
                reattach_parent_to_grandparent(grandparent, parent)
                reset_threads_checking_node(parent)
                maybe_gameover = check_for_1_step_lookahead_gameover(parent)
            for child in unexpanded_children:
                if maybe_gameover:
                    if not child['gameover']: #if it didn't save or win the game, it was a loser
                        num_losing_children+=1
                if child['gameover'] is True: #child color is a loser
                    if child['parent'] is not None:
                        if child['parent']['parent'] is not None:
                            overwhelming_amount = child['overwhelming_amount']
                            update_tree_losses(child['parent']['parent'], overwhelming_amount, gameover=True) #if grandchild lost, parent won, grandparent lost
                else:
                    eval_child(child)  # backprop eval
            if maybe_gameover:
                update_tree_wins(parent['parent'], amount=num_losing_children, gameover=True) #update tree through grandparent who didn't receive the original update

            for grandparent in grandparents:
                update_win_status_from_children(grandparent)  # since parents may have been updated, grandparent must check these copies; maybe less duplication to do it here than in expanded parents loop?
                backpropagate_num_checked_children(grandparent)
            sim_info['game_tree'].extend(expanded_parents)
    return unexpanded_children, over_time

cdef check_for_1_step_lookahead_gameover(dict parent):
    cdef:
        dict game_board = parent['game_board']

    if parent['color'] == 'Black':
        game_over_row = 7
        enemy_piece = 'w'
    else:
        game_over_row = 2
        enemy_piece = 'b'
    return enemy_piece in game_board[game_over_row].values()#Maybe gameover next move




cdef do_updates_in_the_same_process(list unexpanded_nodes, int depth, int depth_limit, np.ndarray NN_output, dict sim_info, lock):
    cdef:
        list unexpanded_children = []
        int i
        dict parent
        dict child_0
        dict child_1

    over_time = False
    append = unexpanded_children.append
    time_to_think = sim_info['time_to_think']

    for i in range(0, len(unexpanded_nodes)):
        parent = unexpanded_nodes[i]
        if time() - sim_info['start_time'] < time_to_think:# and len(sim_info['game_tree'])<10000  # stop updating parents as soon as we go over our time to think
            with lock:
                if parent['threads_checking_node'] <= 1 and (parent['children'] is None):
                    if parent['threads_checking_node'] <= 0:
                        increment_threads_checking_node(parent)
                    abort = False
                else:
                    decrement_threads_checking_node(parent)
                    abort = True
            if not abort:
                children = update_parent(parent, NN_output[i], sim_info, lock)
                if depth+1 < depth_limit and children is not None:  # if we are allowed to enter the outermost while loop again
                    with lock:

                            num_children = len(children)
                            if num_children>=2:
                                child_0 =children [0]
                                if child_0['win_status'] is None and child_0['threads_checking_node']<=0 and not child_0['subtree_being_checked']:
                                    append(children[0])
                                # if time_to_think > 30:
                                #     child_1 = children [1]
                                #     if child_1['win_status'] is None and child_1['threads_checking_node']<=0 and not child_1['subtree_being_checked'] :#if first child wasn't that good #and parent['color'] == 'Black' # and child_0['UCT_multiplier']<1.35
                                #         unexpanded_children.append(children[1])
                            elif num_children==1:
                                child_0 = children[0]
                                if child_0['win_status'] is None and child_0['threads_checking_node'] <= 0 and not child_0['subtree_being_checked']:
                                    append(children[0])


        else:
            reset_threads_checking_node(parent)  # have to iterate over all parents to set this
            over_time = True
    return unexpanded_children, over_time



cdef list update_parent(dict parent, np.ndarray NN_output, dict sim_info, lock):
    cdef list children = []
    with lock:  # Lock after the NN update and check if we still need to update the parent
        if parent['children'] is None:
            abort = False
            sim_info['game_tree'].append(parent)
        else:
            abort = True
            decrement_threads_checking_node(parent)
    if not abort:  # if the node hasn't already been updated by another thread
        children = enumerate_update_and_prune(parent, NN_output, sim_info,lock)
    return children

cpdef update_parents_for_process(list args):#when more than n parents, have a separate process do the updating
    cdef:
        list unexpanded_nodes = args[0]
        np.ndarray NN_output = args[1]
        int depth = args[2]
        int depth_limit = args[3]
        float start_time = args[4]
        int time_to_think = args[5]

    root_color = args[6]
    sim_info = SimulationInfo(stdout)
    sim_info['do_eval'] = False
    lock = Lock()

    unexpanded_children = []
    append = unexpanded_children.append
    over_time = False
    for i in range(0, len(unexpanded_nodes)):
        parent = unexpanded_nodes[i]
        if time() - start_time < time_to_think:  # stop updating parents as soon as we go over our time to think
            with lock:
                if parent['threads_checking_node'] <= 1 and (parent['children'] is None):
                    if parent['threads_checking_node'] <= 0:
                        increment_threads_checking_node(parent)
                    abort = False
                else:
                    decrement_threads_checking_node(parent)
                    abort = True
            if not abort:

                children = update_parent( parent, NN_output[i], sim_info, lock)
                children_to_consider = []
                if depth +1 < depth_limit and len(children)>0:  # if we are allowed to enter the outermost while loop again
                    if parent['color'] == root_color:  # black move
                        best_child = None
                        for child in children:  # walk down children sorted by NN probability
                            if child['win_status'] is None and child['threads_checking_node']<=0 and not child['subtree_being_checked']:
                                best_child = child
                                break
                        if best_child is not None:
                            # children_to_consider = [best_child]
                            append(best_child)
                    else:
                        count = 0
                        while count < len(children) and count < 2:
                            append(children[count])
                            count += 1
                #         if len(children)<3:
                #             children_to_consider = children
                #         else:
                #             children_to_consider = [children[0], children[1]]
                # unexpanded_children.extend(children_to_consider)
        else:
            reset_threads_checking_node(parent) # have to iterate over all parents to set this
            over_time = True
    return unexpanded_nodes, unexpanded_children, over_time

def reattach_parent_to_children(parent, children):
    for child in children:
        child['parent'] =parent
        eval_child(child)
        check_for_winning_move(child)

def reattach_parent_to_grandparent(grandparent, parent):
    for i in range(0, len(grandparent['children'])):
        if parent['index'] == grandparent['children'][i]['index']:
            grandparent['children'][i] = parent
            parent['parent'] = grandparent
            break


cdef list enumerate_update_and_prune(dict parent, np.ndarray NN_output, dict sim_info, lock):
    cdef:
        list children = []
        list pruned_children
        list player_pieces
        list children_as_moves
        str color
        str move

    color = parent['color']
    if color == 'White':
        player_pieces = parent['white_pieces']
    else:
        player_pieces = parent['black_pieces']
    children_as_moves = enumerate_legal_moves_using_piece_arrays(color, parent['game_board'], player_pieces)
    children = [get_child(parent, move, NN_output,sim_info, lock) for move in children_as_moves]
    pruned_children = assign_children(parent, children, lock)
    return pruned_children

def get_best_child_val(parent, NN_output, top_children_indexes):
    best_child_val = 0
    rank = 0 # sometimes top prediction isn't the highest ranked.
    for top_child_index in top_children_indexes:  # find best legal child value
        top_move = move_lookup_by_index(top_child_index, parent['color'])
        if check_legality_MCTS(parent['game_board'], top_move):
            best_child_val = NN_output[top_child_index]
            break
        else:
            rank += 1
    return best_child_val, rank

cdef get_num_children_to_consider(dict parent):


    height = parent[ 'height']

    if parent['color'] == 'Black':  # opponent moves
        if height>= 80:
            parent['num_to_consider'] =2#8
            parent['num_to_keep'] =  2 # else play with child val threshold

        elif height >= 70:
            parent['num_to_consider'] = 2#6
            parent['num_to_keep'] = 2
        # 2?   65-69      #??
        elif height < 70 and height >= 65:
            parent['num_to_consider'] = 2#6
            parent['num_to_keep'] = 2 # else play with child val threshold?
        # # # 4?   60-64
        elif height < 65 and height >= 60:
            parent['num_to_consider'] = 0#8
            parent['num_to_keep'] = 4 #3?  else play with child val threshold
        # 7 or 4?   50-59
        elif height < 60 and height >= 50:
            parent['num_to_consider'] = 0#8
            parent['num_to_keep'] = 4 #3?   else play with child val threshold
        # 5    40-49
        elif height < 50 and height >= 40:
            parent['num_to_keep'] =  4#7 #else play with child val threshold?
        # 2    30-39
        elif height < 40 and height >= 30:
            parent['num_to_keep'] = 4 #7 # else play with child val threshold?
        # 2    20-29
        elif height < 30 and height >= 20:
            parent['num_to_keep'] =  3 #else play with child val threshold?
         # 2    0-19
        elif height < 20 and height >= 0:
            parent['num_to_keep'] =  3 #else play with child val threshold?
        else: #2?
            parent['num_to_keep'] = 1  # else play with child val threshold?
    else:
            # 3?   61-69
        if height >= 70:
            parent['num_to_consider'] = 1
            parent['num_to_keep'] = 1 # else play with child val threshold # else play with child val threshold? WaNN missed an easy win and thought it was doomed at height 53
            # 52-60
        elif height < 70 and height >= 61:#2?
            parent['num_to_consider'] = 2
            parent['num_to_keep'] = 1 # else play with child val threshold2#2  # else play with child val threshold? WaNN missed an easy win and thought it was doomed at height 53
            # 52-60
        elif height < 61 and height >= 52:
           parent['num_to_consider'] = 2
           parent['num_to_keep'] = 1 # else play with child val threshold#3  # else play with child val threshold? WaNN missed an easy win and thought it was doomed at height 53
            # 3?   40-51
        elif height < 52 and height >= 40:  # 40?
           parent['num_to_consider'] = 3
           parent['num_to_keep'] = 1 # else play with child val threshold#2  # else play with child val threshold? missed an easy win and thought it was doomed at 2 height 53
        elif height < 40 and height >= 35:  # 40?
           parent['num_to_consider'] = 3
           parent['num_to_keep'] = 1  # else play with child val threshold#2  # else play with child val threshold? missed an easy win and thought it was doomed at 2 height 53

        elif height < 20 and height >= 0:
            parent['num_to_keep'] =  1#2 #else play with child val threshold?
        else:
            parent['num_to_keep'] = 1#1 # else play with child val threshold?
    # else:
    #     num_top_to_consider = 999
    #     # num_top_to_consider = 3
    return parent['num_to_keep']



cdef dict get_child(dict parent, str move, np.ndarray NN_output, dict sim_info, lock):
    cdef dict child = init_unique_child_node_and_board(move, parent)
    check_for_winning_move(child)  # 1-step lookahead for gameover
    if child['gameover']:
        sim_info['game_tree'].append(child)
    update_child(child, NN_output, sim_info, do_eval=False)
    return child

cdef assign_children(dict parent, list children, lock):
    cdef:
        list parent_children = []
        list other_children
        double best_val
        int game_over_row
        str enemy_piece
        dict child
        dict game_board

    with lock:
        decrement_threads_checking_node(parent)


        if len(children) > 0:
            if parent['children'] is None:
                # get_num_children_to_consider(parent)


                children.sort(key=lambda x: x['UCT_multiplier'], reverse=True)#sort them by probability
                # if best_val <1.30 and parent['color'] =='White':
                #     update_tree_losses(parent, 10, gameover=True)#maybe the tree with these patterns wins?

                parent['best_child'] = children[0]

                if parent['color'] == 'Black':
                    game_over_row = 7
                    enemy_piece = 'w'
                else:
                    game_over_row = 2
                    enemy_piece = 'b'
                game_board = parent['game_board']

                if enemy_piece in game_board[game_over_row].values():#Maybe gameover next move
                    for child in children:
                        move = move_lookup_by_index(child['index'], get_opponent_color(child['color']))
                        if enemy_piece == game_board[int(move[4])][move[3]]: #a game saving move
                            child['gameover_visits'] = 1000 #some arbitrarily good prior values
                            child['gameover_wins'] = 0
                            child['visits'] = 65536
                            child['wins'] = 0
                            parent_children.append(child) #only check the children without a win_status
                        elif not child['gameover']: #if it didn't save or win the game, it was a loser
                            set_game_over_values_1_step_lookahead(child)

                    parent['children'] = children

                elif parent['num_to_keep']  != 999:
                    get_num_children_to_consider(parent)
                    best_val = children[0]['UCT_multiplier']
                    parent_children = []
                    other_children = []
                    if best_val >1.9: # > 90%
                        parent['num_to_keep'] = 1
                    min_val_threshold = (best_val-1)/2.5
                    threshold_val = 0.10
                    for i in range(0, len(children)):
                        # if len(parent_children) < 2:# and parent['color'] == 'White'
                        #     threshold_val = 0.25
                        # else:
                        #     threshold_val = 0.10
                        if i < parent['num_to_keep'] or (best_val - children[i]['UCT_multiplier'] < threshold_val and children[i]['UCT_multiplier'] -1 > min_val_threshold) or children[i]['gameover']:#or best_val - children[i]['UCT_multiplier'] < .20
                            parent_children.append(children[i])
                        else: #when appending other children to children later on, will still be in sorted order UNLESS there were gameovers in the middle, in which case who cares.
                            other_children.append(children[i])
                    parent['children'] = parent_children
                    eval_children(parent_children)
                    parent['other_children'] = other_children
                else:
                    parent['children'] = children
                    parent_children = children
                    eval_children(children)#slightly more efficient to do them as a batch

                if parent['num_to_consider'] == 0 or (parent['other_children'] is None or len (parent['other_children']) == 0): # len (parent['children']) >=  Virtually reexpanded;  else may try to reexpand and thrash around in tree search
                    parent['reexpanded_already'] = True
                # if parent['parent'] is None:
                #     parent['children'] = [parent['children'][0]]
                update_win_status_from_children(parent)
                backpropagate_num_checked_children(parent)
                update_num_children_being_checked(parent)
    # if parent['children'] is None:
    #     breakpoint = True
    return parent_children


cdef dict init_unique_child_node_and_board(str child_as_move, dict parent):
    cdef:
        int child_index = index_lookup_by_move(child_as_move)
        dict child_board
        list child_white_pieces
        list child_black_pieces
        str child_color
        dict child
    child_board, child_white_pieces, child_black_pieces, child_color = get_child_attributes(parent, child_as_move)
    child = TreeNode(child_board, child_white_pieces, child_black_pieces, child_color, child_index, parent, parent['height'] + 1)
    return child

cdef check_for_twin(dict parent, int child_index):
    duplicate = False
    if parent['children'] is not None:
        for child in parent['children']:
            if child['index'] ==child_index:
                duplicate = True
                break
    return duplicate

cdef get_child_attributes(dict parent, str child_as_move):
    cdef:
        str child_color = get_opponent_color(parent['color'])
        dict child_board
        str player_piece_to_add
        str player_piece_to_remove
        list child_white_pieces
        list child_black_pieces

    child_board, player_piece_to_add, player_piece_to_remove, remove_opponent_piece\
        = move_piece_update_piece_arrays(parent['game_board'], child_as_move, parent['color'])

    child_white_pieces, child_black_pieces \
        = update_piece_arrays(parent, player_piece_to_add, player_piece_to_remove, remove_opponent_piece)
    return child_board, child_white_pieces, child_black_pieces, child_color

cdef update_piece_arrays(dict parent, player_piece_to_add, player_piece_to_remove, remove_opponent_piece):
    cdef:
        list player_pieces
        list opponent_pieces
        list child_white_pieces
        list child_black_pieces

    # slicing is the fastest way to make a copy
    if parent['color'] == 'White':
        player_pieces = parent['white_pieces'][:]
        opponent_pieces = parent['black_pieces'][:]
        child_white_pieces = player_pieces
        child_black_pieces = opponent_pieces
    else:
        player_pieces = parent['black_pieces'][:]
        opponent_pieces = parent['white_pieces'][:]
        child_white_pieces = opponent_pieces
        child_black_pieces = player_pieces
    player_pieces[player_pieces.index(player_piece_to_remove)] = player_piece_to_add
    if remove_opponent_piece:
        opponent_pieces.remove(player_piece_to_add)
    return child_white_pieces, child_black_pieces

# def get_child(parent, move, NN_output, sim_info, lock):
#     child = init_unique_child_node_and_board(move, parent)
#     if child is not None:
#         check_for_winning_move(child)  # 1-step lookahead for gameover
#         if child['gameover']:
#             sim_info['game_tree'].append(child)
#         update_child(child, NN_output, sim_info, do_eval=False)
#     return child
#
# def assign_children(parent, children, lock):
#     with lock:
#         decrement_threads_checking_node(parent)
#
#
#         if len(children) > 0:
#             if parent['children'] is None:
#                 get_num_children_to_consider(parent)
#                 parent_children = []
#                 other_children = []
#                 children.sort(key=lambda x: x['UCT_multiplier'], reverse=True)#sort them by probability
#                 best_val = children[0]['UCT_multiplier']
#                 # if best_val <1.30 and parent['color'] =='White':
#                 #     update_tree_losses(parent, 10, gameover=True)#maybe the tree with these patterns wins?
#
#                 parent['best_child'] = children[0]
#
#                 if parent['color'] == 'Black':
#                     game_over_row = 7
#                     enemy_piece = 'w'
#                 else:
#                     game_over_row = 2
#                     enemy_piece = 'b'
#                 gameover_next_move = enemy_piece in parent['game_board'][game_over_row].values()
#                 if gameover_next_move:
#                     for i in range(0, len(children)):
#                         #game_winning or game_saving moves only (if not game_saving, it'll be a loss)
#                         if children[i]['game_saving_move'] or children[i]['gameover']:  # or best_val - children[i]['UCT_multiplier'] < .20
#                             parent_children.append(children[i])
#                         else:  # when appending other children to children later on, will still be in sorted order UNLESS there were gameovers in the middle, in which case who cares.
#                             set_game_over_values_1_step_lookahead(children[i])
#                             parent_children.append(children[i])
#                     parent['children'] = parent_children
#
#
#
#
#
#                 elif parent['num_to_keep']  != 999:
#                     if best_val >1.9: # > 90%
#                         parent['num_to_keep'] = 1
#                     min_val_threshold = (best_val-1)/2.5
#                     threshold_val = 0.10
#                     for i in range(0, len(children)):
#                         # if len(parent_children) < 2:# and parent['color'] == 'White'
#                         #     threshold_val = 0.25
#                         # else:
#                         #     threshold_val = 0.10
#                         if i < parent['num_to_keep'] or (best_val - children[i]['UCT_multiplier'] < threshold_val and children[i]['UCT_multiplier'] -1 > min_val_threshold) or children[i]['gameover']:#or best_val - children[i]['UCT_multiplier'] < .20
#                             parent_children.append(children[i])
#                         else: #when appending other children to children later on, will still be in sorted order UNLESS there were gameovers in the middle, in which case who cares.
#                             other_children.append(children[i])
#                     parent['children'] = parent_children
#                     eval_children(parent_children)
#                     parent['other_children'] = other_children
#                 else:
#                     parent['children'] = children
#                     eval_children(children)#slightly more efficient to do them as a batch
#
#                 if parent['num_to_consider'] == 0 or (parent['other_children'] is None or len (parent['other_children']) == 0): # len (parent['children']) >=  Virtually reexpanded;  else may try to reexpand and thrash around in tree search
#                     parent['reexpanded_already'] = True
#                 # if parent['parent'] is None:
#                 #     parent['children'] = [parent['children'][0]]
#                 update_win_status_from_children(parent)
#                 backpropagate_num_checked_children(parent)
#     # if parent['children'] is None:
#     #     breakpoint = True
#     return parent['children']
#
#
# def init_unique_child_node_and_board(child_as_move, parent):
#     child_index = index_lookup_by_move(child_as_move)
#     already_in_parent = check_for_twin(parent, child_index)
#     if not already_in_parent:
#         child_board, child_white_pieces, child_black_pieces, child_color = get_child_attributes(parent, child_as_move)
#         child = TreeNode(child_board, child_white_pieces, child_black_pieces, child_color, child_index, parent, parent['height'] + 1)
#     else:
#         child = None
#     return child
#
# def check_for_twin(parent, child_index):
#     duplicate = False
#     if parent['children'] is not None:
#         for child in parent['children']:
#             if child['index'] ==child_index:
#                 duplicate = True
#                 break
#     return duplicate
#
# def get_child_attributes(parent, child_as_move):
#     child_color = get_opponent_color(parent['color'])
#
#     child_board, player_piece_to_add, player_piece_to_remove, remove_opponent_piece\
#         = move_piece_update_piece_arrays(parent['game_board'], child_as_move, parent['color'])
#
#     child_white_pieces, child_black_pieces \
#         = update_piece_arrays(parent, player_piece_to_add, player_piece_to_remove, remove_opponent_piece)
#     return child_board, child_white_pieces, child_black_pieces, child_color
#
# def update_piece_arrays(parent, player_piece_to_add, player_piece_to_remove, remove_opponent_piece):
#     # slicing is the fastest way to make a copy
#     if parent['color'] == 'White':
#         player_pieces = parent['white_pieces'][:]
#         opponent_pieces = parent['black_pieces'][:]
#         child_white_pieces = player_pieces
#         child_black_pieces = opponent_pieces
#     else:
#         player_pieces = parent['black_pieces'][:]
#         opponent_pieces = parent['white_pieces'][:]
#         child_white_pieces = opponent_pieces
#         child_black_pieces = player_pieces
#     player_pieces[player_pieces.index(player_piece_to_remove)] = player_piece_to_add
#     if remove_opponent_piece:
#         opponent_pieces.remove(player_piece_to_add)
#     return child_white_pieces, child_black_pieces


def init_new_root(new_root_as_move, new_root_game_board, player_color, new_root_parent, policy_net, sim_info, lock): #online reinforcement learning if wanderer made a move that wasn't in the tree



    if new_root_parent['children'] is None:# in case parent was never expanded
        print("New root's parent had no children", file=sim_info['file'])

        new_root_parent['threads_checking_node'] = 1
        expand_descendants_to_depth_wrt_NN([new_root_parent], 0, 1, sim_info, lock,
                                           policy_net)

        if new_root_parent['children'] is None: #still none means the pruning was too aggressive; still append this child.
            print("Pruning too aggressive: New root's parent still has no children after expansion", file=sim_info['file'])

            # new_root_index = index_lookup_by_move(new_root_as_move)
            # new_root = TreeNode(new_root_game_board, player_color, new_root_index, new_root_parent,
            #                     new_root_parent['height'] + 1)

            new_root = init_unique_child_node_and_board(new_root_as_move, new_root_parent)
            if new_root is None:
                exit(10)
            NN_output = policy_net.evaluate([new_root_parent])[0]
            top_children_indexes = get_top_children(NN_output)
            update_child(new_root, NN_output, top_children_indexes,
                         0, sim_info)  # update prior values on the node NOTE: never a game over
            rank = list(top_children_indexes).index(new_root['index'])
            print("PRUNING INVESTIGATION: new root's probability = %{prob} Rank = {rank}".format(
                prob=((new_root['UCT_multiplier'] - 1) * 100), rank=rank +1),
                file=sim_info['file'])
            new_root_parent['children'] = [new_root]

        else: #now expanded with some children; check if new root is one of them
            now_in_parent = False
            duplicate_child = None
            for child in new_root_parent['children']:
                if child['game_board'] ==new_root_game_board:
                    print("Pruning Fine: New root is now in parent's children after expansion",
                          file=sim_info['file'])

                    duplicate_child = child
                    now_in_parent  = True

            if not now_in_parent:
                print("Pruning too aggressive: New root's parent still did not have the actual new root after expansion",
                      file=sim_info['file'])

                # new_root_index = index_lookup_by_move(new_root_as_move)
                # new_root = TreeNode(new_root_game_board, player_color, new_root_index, new_root_parent,
                #                     new_root_parent['height'] + 1)

                new_root = init_unique_child_node_and_board(new_root_as_move, new_root_parent)
                if new_root is None:
                    exit(11)
                NN_output = policy_net.evaluate([new_root_parent])[0]
                top_children_indexes = get_top_children(NN_output)
                update_child(new_root, NN_output, top_children_indexes,
                             len(new_root_parent['children']), sim_info)  # update prior values on the node NOTE: never a game over
                rank = list(top_children_indexes).index(new_root['index'])
                print("PRUNING INVESTIGATION: new root's probability = %{prob} Rank = {rank}".format(
                    prob=((new_root['UCT_multiplier'] - 1) * 100), rank=rank +1),
                    file=sim_info['file'])
                new_root_parent['children'].append(new_root) #attach new root to parent
            else:
                new_root = duplicate_child

    else:#has kids but new_root wasn't in them.
        print("Pruning investigation: New root's parent did not have new root after initial expansion",
              file=sim_info['file'])
        # new_root_index = index_lookup_by_move(new_root_as_move)
        #
        # new_root = TreeNode(new_root_game_board, player_color, new_root_index, new_root_parent,
        #                     new_root_parent['height'] + 1)

        new_root = init_unique_child_node_and_board(new_root_as_move, new_root_parent)
        if new_root is None:
                exit(12)
        NN_output = policy_net.evaluate([new_root_parent])[0]
        top_children_indexes = get_top_children(NN_output)
        update_child(new_root, NN_output, top_children_indexes,
                     len(new_root_parent['children']), sim_info)  # update prior values on the node NOTE: never a game over
        rank = list(top_children_indexes).index(new_root['index'])
        print("PRUNING INVESTIGATION: new root's probability = %{prob} Rank = {rank}".format(
            prob=((new_root['UCT_multiplier'] - 1) * 100), rank=rank +1),
            file=sim_info['file'])
        new_root_parent['children'].append(new_root)  # attach new root to parent

    backpropagate_num_checked_children(new_root_parent)
    update_win_status_from_children(new_root_parent, new_subtree=True)
    return new_root

#


cdef void check_for_winning_move(dict child_node, rollout=False):
    cdef int index = child_node['index']
    if index > 131 and index !=154:
        set_game_over_values(child_node)

def set_game_over_values(node):
    node['gameover'] =True
    node['subtree_checked'] =True
    node['wins'] = 0 # this node will neverwin;
    node['gameover_visits'] = 65536
    node['visits'] = 65536
    node['win_status'] = False
    update_tree_losses(node, gameover=True) #keep agent away from subtree and towards subtrees of the same level

def set_game_over_values_1_step_lookahead(node):
    node['visits'] = 65536
    node['wins'] = 65536 # this node will neverwin;
    node['gameover_wins'] = 65536
    node['gameover_visits'] = 65536
    node['win_status'] = True
    update_tree_wins(node, gameover=True) #keep agent away from subtree and towards subtrees of the same level
# 
# def reset_game_over_values(node):
#     if node['gameover'] is True:
#         if node['win_status'] is False:
#             update_tree_wins(node, -(node['visits']-1))
#         elif node['win_status'] is True:
#             update_tree_losses(node, -(node['wins']-1))
# 
# def true_random_rollout_EOG_thread_func(node):
#     depth = 0
#     while not node['gameover'] and depth <=4:
#         if node['children'] is None:
#             expand_node(node, rollout=True)
#         while node['children'] is not None:
#             node = sample(node['children'], 1)[0] #
#             depth += 1
#     random_rollout(node)
#     return node
# 
# def true_random_rollout_EOG(node):
#     # with Pool(processes=10) as process:
#     #     outcome_node = process.apply_async(true_random_rollout_EOG_thread_func, [node])
#     #     outcome_node = outcome_node.get()
#     outcome_node = true_random_rollout_EOG_thread_func(node)
#     # if outcome_node['color'] ==node['color']:
#     #     if outcome_node['win_status'] is True:
#     #         update_tree_wins(node, 1)
#     #     elif outcome_node['win_status'] is False:
#     #         update_tree_losses(node, 1)
#     # else:
#     #     if outcome_node['win_status'] is True:
#     #         update_tree_losses(node, 1)
#     #     elif outcome_node['win_status'] is False:
#     #         update_tree_wins(node, 1)