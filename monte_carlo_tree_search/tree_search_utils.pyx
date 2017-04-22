#cython: language_level=3, boundscheck=False

from math import log, sqrt, floor
import random
from bottleneck import argpartition
from numpy import argsort
# from time import time

class SimulationInfo():
    def __init__(self, file):
        self.file= file
        self.counter = 0
        self.prev_game_tree_size = 0
        self.game_tree = []
        self.game_tree_height = 0
        self.start_time = None
        self.time_to_think = None
        self.root = None
        self.game_num = 0
        self.do_eval = True
        self.main_pid = -1
        self.root_thread_counter = 0

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.counter = 1
        self.prev_game_tree_size = 0
        self.game_tree = []
        self.game_tree_height = 0
        self.game_node_height = []  # synchronized with nodes in game_tree
        self.start_time = None

#backpropagate wins
def update_tree_wins(node, amount=1): #visits and wins go together
    node.wins += amount
    node.visits += amount
    parent = node.parent
    if parent is not None: #node win => parent loss_init
        update_tree_losses(parent, amount)

#backpropagate losses
def update_tree_losses(node, amount=1): # visit and no win = loss_init
    node.visits += amount
    parent = node.parent
    if parent is not None: #node loss_init => parent win
        update_tree_wins(parent, amount)

#backpropagate guaranteed win status
def update_win_statuses(node, win_status, new_subtree=False):
    if node.color == 'Black' and win_status is False and not node.reexpanded_already:
        node.reexpanded = True
    else:
        node.win_status = win_status
        parent = node.parent
        if parent is not None:#parent may now know if it is a win or loss_init.
            update_win_status_from_children(parent, new_subtree)

def update_win_status_from_children(node, new_subtree=False):
    win_statuses = get_win_statuses_of_children(node)
    set_win_status_from_children(node, win_statuses, new_subtree)

def get_win_statuses_of_children(node):
    win_statuses = []
    if node.children is not None:
        for child in node.children:
            win_statuses.append(child.win_status)
    return win_statuses

def set_win_status_from_children(node, children_win_statuses, new_subtree=False):
    if False in children_win_statuses: #Fact: if any child is false => parent is true
        update_win_statuses(node, True, new_subtree)  # some kid is a loser, I have some game winning move to choose from
    elif True in children_win_statuses and not False in children_win_statuses and not None in children_win_statuses:
        update_win_statuses(node, False, new_subtree)#all children winners = node is a loss_init no matter what
    elif new_subtree: #appended from opponent move not already in tree
        update_win_statuses(node, None, new_subtree) #maybe this subtree had an inaccurate win_status before, ensure tree is correct. since this is done upon root assignment, won't take time in the middle of search.
       # some kids are winners, some kids are unknown => can't say anything with certainty

def subtract_child_wins_and_visits(node, child): #for pruning tree built by MCTS using async updates
    parent = node
    while parent is not None:
        parent.wins -= child.wins
        parent.visits -= child.visits
        parent = parent.parent


def _crement_threads_checking_node(node, amount):
    if amount == 0:
        node.threads_checking_node = 0
    else:
        node.threads_checking_node +=amount
    parent = node.parent
    if parent is not None:
        if node.threads_checking_node <=0:
            parent.subtree_being_checked = False
            if parent.num_children_being_checked > 0:
                parent.num_children_being_checked -= 1
        else:
            parent.num_children_being_checked += 1
            num_children = len(parent.children)
            if num_children == parent.num_children_being_checked:
                parent.subtree_being_checked = True


            
def increment_threads_checking_node(node):
    _crement_threads_checking_node(node, 1)
        
def decrement_threads_checking_node(node):
    _crement_threads_checking_node(node, -1)

def reset_threads_checking_node(node):
    _crement_threads_checking_node(node, 0)

def update_num_children_being_checked(node):
    children_being_checked=0
    if node.children is not None:
        for child in node.children:
            if child.threads_checking_node > 0:
                children_being_checked+=1
    node.num_children_being_checked = children_being_checked
    if node.num_children_being_checked == len(node.children):
        node.subtree_being_checked = True
    else:
        node.subtree_being_checked = False


def choose_UCT_move(node, start_time, time_to_think, sim_info):
    best = None #shouldn't ever return None
    if node.children is not None:
        best = find_best_UCT_child(node, start_time, time_to_think, sim_info)
    return best  #because a win for me = a loss_init for child

def choose_UCT_or_best_child(node, start_time, time_to_think, sim_info):
    best = None  # shouldn't ever return None
    num_children = len(node.children)
    if num_children == 1:
        best = node.children[0]
    elif node is sim_info.root:
        if num_children>1:
            best = node.children[sim_info.root_thread_counter%num_children]
            sim_info.root_thread_counter+=1
    else:
        if node.best_child is not None: #return best child if not already previously expanded
            if node.best_child.win_status is None and node.best_child.visited is False: # and not node.best_child.subtree_checked ...  node.best_child.visited is False and
                best = node.best_child
            else:
                best = find_best_UCT_child(node, start_time, time_to_think, sim_info)
            node.best_child.visited = True
        elif node.children is not None: #if this node has children to choose from: should always happen
            best = find_best_UCT_child(node, start_time, time_to_think, sim_info)
    return best  # because a win for me = a loss for child

# def choose_UCT_or_best_child(node, start_time, time_to_think, sim_info):
#     best = None  # shouldn't ever return None
#     for child in node.children:
#         if child.win_status is None and child.threads_checking_node <= 0:
#             best = child
#             break
#     # if node.height %2 == 0: #white's move, pick move with highest probability
#     #     for child in node.children:
#     #         if child.win_status is None and child.threads_checking_node <=0:
#     #             best = child
#     #             break
#     # else: #black's move
#     #     if best is None:
#     #         if node.best_child is not None: #return best child if not already previously expanded
#     #             if node.best_child.visited is False and node.best_child.win_status is None:
#     #                 best = node.best_child
#     #             else:
#     #                 best = find_best_UCT_child(node, start_time, time_to_think, sim_info)
#     #             node.best_child.visited = True
#     #         elif node.children is not None: #if this node has children to choose from: should always happen
#     #             best = find_best_UCT_child(node, start_time, time_to_think, sim_info)
#     return best  # because a win for me = a loss_init for child

def choose_best_true_winner(node_children):
    best_nodes = []
    best = None
    if node_children is not None:
        for child in node_children:
            net_wins = child.wins_down_this_tree - child.losses_down_this_tree
            if net_wins > 0:
                best_nodes.append(child)

        if len(best_nodes) > 0:
            best_net_wins = best_nodes[0].wins_down_this_tree - best_nodes[0].losses_down_this_tree
            best = best_nodes[0]

            for potential_winner in best_nodes:  # get best
                num_true_wins = potential_winner.wins_down_this_tree - potential_winner.losses_down_this_tree
                if num_true_wins > best_net_wins:
                    best_net_wins = num_true_wins
                    best = potential_winner

            for potential_winner in best_nodes:  # find another best with a higher win-rate
                num_true_wins = potential_winner.wins_down_this_tree - potential_winner.losses_down_this_tree
                if num_true_wins == best_net_wins and \
                        ((potential_winner.visits - potential_winner.wins) / potential_winner.visits) >= (
                        (best.visits - best.wins) / best.visits):
                    best = potential_winner

    return best

def find_best_UCT_child(node, start_time, time_to_think, sim_info):
    parent_visits = node.visits
    best = None
    #only stop checking children with win statuses after height 60 as we may need to reexpand a node marked as a win/loss_init
    if node.win_status is not None:#search subtrees that need to be reexpanded (probably won't happen anymore)
        viable_children = list(filter(lambda x:  x.reexpanded and x.threads_checking_node <=0, node.children))
        if len(viable_children) == 0:#search subtrees until they have a win status
            viable_children = list(filter(lambda x:  (x.win_status is None and not x.subtree_being_checked) and (x.threads_checking_node <=0 or x.children is not None), node.children))
        if len(viable_children) == 0:#search until all subtrees are checked
            viable_children = list(filter(lambda x:  not x.subtree_checked and not x.subtree_being_checked and (x.threads_checking_node <=0 or x.children is not None), node.children))
    else:#search subtrees that need to be reexpanded
        viable_children = list(filter(lambda x:  x.reexpanded and x.threads_checking_node <=0, node.children))
        if len(viable_children) == 0:#search subtrees until they have a win status
          viable_children = list(filter(lambda x:  (x.win_status is None and not x.subtree_being_checked ) and (x.threads_checking_node <=0 or x.children is not None), node.children))
    if len(viable_children)>0:
        best = viable_children[0]
        best_val = get_UCT(best, parent_visits, start_time, time_to_think, sim_info)
        children_to_check = False

        for i in range(1, len(viable_children)):
            #TODO: play with search after a height (ex. if keeping all children and we know win_status, we don't need to search those subtrees anymore)

            # if (node.win_status is True and node.height <60) or node.win_status is None:
            #     predicate = viable_children[i].win_status is None  # only consider subtrees where we don't already know what's going to happen
            # else:  # all children are True (winners)
            #     predicate = True  # the node is a loser (all children are winners); keep checking in case opponent makes a move into a subtree we wouldn't have expected

            #for RL, just constrain the search space and assume wanderer has a win status if we do as well.
            # predicate = viable_children[i].win_status is None  # only consider subtrees where we don't already know what's going to happen
            #
            # if predicate:
                child_value = get_UCT(viable_children[i], parent_visits, start_time, time_to_think, sim_info)
                if child_value > best_val:
                    best = viable_children[i]
                    best_val = child_value
                    children_to_check = True

        if not children_to_check and best.win_status is False:  # all children were False (losers);
            # print("RL Error: UCT shouldn't have chosen a subtree with children who have win statuses")
            for i in range(1, len(viable_children)):
                    child_value = get_UCT(viable_children[i], parent_visits, start_time, time_to_think, sim_info)
                    if child_value > best_val:
                        best = viable_children[i]
                        best_val = child_value

        # if best.children is None:
        #     best.threads_checking_node += 1
    return best

def get_UCT(node, parent_visits, start_time, time_to_think, sim_info):
    if node.visits == 0:
        UCT = 998 #necessary for MCTS without NN initialized values
    else:
        overwhelming_amount = 65536
        NN_scaling_factor = 1000


        # # 03/11/2017 games actually good with this and no division, but annealing seems right?
        stochasticity_for_multithreading = random.random()  #/2.4 # keep between [0,0.417] => [1, 1.417]; 1.414 ~ √2
        stoch_for_NN_weighting = 1- (stochasticity_for_multithreading/4)#since this can get so huge in the beginning,
        # maybe bouncing it around will be good so threads don't knock into each other?
        # # #TODO test this. SEEMS like a good idea since it will explore early and exploit later
        # annealed_factor = 1 - (
        # (start_time - time()) / time_to_think)  # starts at 1 and trends towards 0 as search proceeds
        # # with stochasticity multiplier between .5 and 1 so multithreading sees different values
        # stochasticity_for_multithreading = (1 - random.random() / 2) * max(0.25,
        #                                                                    annealed_factor)  # in printed stats games, probably never got to a low value

        # stochasticity_for_multithreading = (random.random()*4) * max(0.25, annealed_factor) #in printed stats games, probably never got to a low value

            # exploration_constant = 0.1 + stochasticity_for_multithreading # 1.414 ~ √2
        exploration_constant =  stochasticity_for_multithreading # 1.414 ~ √2

        if node.visits >= overwhelming_amount:
            norm_visits = floor(node.visits / overwhelming_amount)+ (node.visits % overwhelming_amount)
            parent_visits = floor(parent_visits/overwhelming_amount) + (parent_visits % overwhelming_amount)
        else:
            norm_visits = node.visits
        if node.wins >= overwhelming_amount:
            norm_wins = floor(node.wins/overwhelming_amount) + (node.wins % overwhelming_amount)
        else:
            norm_wins = node.wins
        NN_weighting = (NN_scaling_factor*(node.UCT_multiplier - 1))/(1+norm_visits)

        norm_loss_rate = (norm_visits-norm_wins)/norm_visits
        exploitation_factor = norm_loss_rate# losses / visits of child = wins / visits for parent

        # exploitation_factor = (node.visits - node.wins) / node.visits  # losses / visits of child = wins / visits for parent
        exploration_factor = exploration_constant * sqrt(log(1+parent_visits) / norm_visits)
        UCT = (exploitation_factor + exploration_factor)
    return UCT + NN_weighting #* (node.UCT_multiplier ) #UCT from parent's POV

def randomly_choose_a_winning_move(node, game_num): #for stochasticity: choose among equally successful children
    best_nodes = []
    if node.children is not None:
        win_can_be_forced, best_nodes = check_for_forced_win(node.children, game_num)
        if not win_can_be_forced:
            if node.win_status is False:
                best_nodes.append(node.children[0])

            else:
                for child in node.children: #sorted by prob
                    if child.win_status is not True and child.wins/child.visits <=.50:
                        best_nodes.append(child)
                        break


            # #to stay inside policy net's prediction?
            # if node.best_child is not None:
            #    best = node.best_child
            #    if best.win_status is not True:
            #       best_nodes.append(best)
            #       #loss_rate =  (best.visits - best.wins)/best.visits
            #       # if loss_rate > .30:

            if len(best_nodes) == 0:
                best_nodes = get_best_children(node.children, game_num)
    if len(best_nodes) == 0:
        breakpoint = True
    return random.sample(best_nodes, 1)[0]  # because a win for me = a loss for child

# def randomly_choose_a_winning_move(node, game_num): #for stochasticity: choose among equally successful children
#     best_nodes = []
#     if node.children is not None:
#         win_can_be_forced, best_nodes = check_for_forced_win(node.children, game_num)
#         if not win_can_be_forced:
#             best_nodes = get_best_children(node.children, game_num)
#     if len(best_nodes) == 0:
#         breakpoint = True
#     return random.sample(best_nodes, 1)[0]  # because a win for me = a loss_init for child

def check_for_forced_win(node_children, game_num):
    guaranteed_children = []
    forced_win = False
    for child in node_children:
        if child.win_status is False:
            guaranteed_children.append(child)
            forced_win = True
    if len(guaranteed_children) > 0: #TODO: does it really matter which losing child is the best if all are losers?
        guaranteed_children = get_best_children(guaranteed_children, game_num)
    return forced_win, guaranteed_children


def get_best_children(node_children, game_num):#TODO: make sure to not pick winning children?
    best, best_val = get_best_child(node_children)
    # best, best_val = get_best_most_visited_child(node_children)
    best_nodes = []
    NN_scaling_factor = 1000
    overwhelming_amount = 65536

    for child in node_children:  # find equally best children
        # NN_scaling_factor = 1#((child.UCT_multiplier - 1) / scaling_handicap) + 1
        NN_weighting = (NN_scaling_factor*(child.UCT_multiplier - 1))/(1+child.parent.visits)
        if child.visits >= overwhelming_amount:
            child_visits_norm = floor(child.visits / overwhelming_amount)+ (child.visits % overwhelming_amount) 
        else:
            child_visits_norm = child.visits
        if child.wins >= overwhelming_amount:
            child_wins_norm = floor(child.visits / overwhelming_amount) + (child.visits % overwhelming_amount)
        else:
            child_wins_norm = child.visits
            
        child_loss_rate = (child_visits_norm - child_wins_norm) / child_visits_norm


        if not child.win_status == True: #only consider children who will not lead to a win for opponent
            if child.visits > 0:
                child_NN_scaled_loss_rate = child_loss_rate# + NN_weighting

                if child_NN_scaled_loss_rate == best_val:
                    if best.visits == child.visits:
                        best_nodes.append(child)
                        # should now have list of equally best children
    if len(best_nodes) == 0: #all children are winners => checkmated, just make the best move you have
        best_nodes.append(best)
    return best_nodes

def get_best_child(node_children, non_doomed = True):
    NN_scaling_factor = 1000#+(game_num/100)
    overwhelming_amount = 65536
    k = 0
    if non_doomed:
        while k < len(node_children) and (node_children[k].visits <= 0 or node_children[k].win_status is True) :
            k += 1
    else:
        while k < len(node_children) and node_children[k].visits <= 0:
            k += 1
    if k < len(node_children):
        best = node_children[k]
        if best.visits >= overwhelming_amount:
            best_visits_norm = floor(best.visits / overwhelming_amount)+ (best.visits % overwhelming_amount)
        else:
            best_visits_norm = best.visits
        if best.wins >= overwhelming_amount:
            best_wins_norm = floor(best.visits / overwhelming_amount) + (best.visits % overwhelming_amount)
        else:
            best_wins_norm = best.visits

        best_loss_rate = ((best_visits_norm - best_wins_norm) / best_visits_norm)

        NN_weighting = (NN_scaling_factor*(node_children[k].UCT_multiplier - 1)) / (1+node_children[k].parent.visits)

        best_loss_rate = ((node_children[k].visits - node_children[k].wins) / node_children[k].visits)

        best_val_NN_scaled = best_loss_rate #+ NN_weighting

        # probability = node_children[k].UCT_multiplier-1
        # best_val_NN_scaled = (probability+ best_loss_rate)/(1+probability)

        for i in range(k, len(node_children)):  # find best child
            child = node_children[i]
            NN_weighting = (NN_scaling_factor*(child.UCT_multiplier - 1))/(1+child.parent.visits)
            if non_doomed:
                predicate = child.visits > 0 and not child.win_status is True
            else:
                predicate = child.visits > 0
            if predicate: #only consider non-doomed moves

                if child.visits >= overwhelming_amount:
                    child_visits_norm = floor(child.visits / overwhelming_amount)+ (child.visits % overwhelming_amount) 
                else:
                    child_visits_norm = child.visits
                if child.wins >= overwhelming_amount:
                    child_wins_norm = floor(child.visits / overwhelming_amount) + (child.visits % overwhelming_amount)
                else:
                    child_wins_norm = child.visits
                    
                child_loss_rate = (child_visits_norm - child_wins_norm) / child_visits_norm

                child_NN_scaled_loss_rate = child_loss_rate # + NN_weighting

                # probability = (child.UCT_multiplier-1)
                # child_NN_scaled_loss_rate = (child_loss_rate + probability) / (1+probability)
                #and (child.visits / best.visits > 0.3) or best_loss_rate < .5)
                if child_NN_scaled_loss_rate > best_val_NN_scaled:  # get the child with the highest loss_init rate
                    if (best.visits >= overwhelming_amount and child.visits >= overwhelming_amount) or \
                            (best.visits < overwhelming_amount and child.visits >= overwhelming_amount) or \
                            (best.visits < overwhelming_amount and child.visits < overwhelming_amount) or \
                            ((best_loss_rate) < .30):
                        # if both have searched to game overs, (best case # 1)
                        # if neither have searched to game overs,
                        # if new child has searched to a gameover and current best hasn't (best case # 2)
                        # if new child hasn't searched to a gameover, best has, but new child has a better loss_init-rate (i.e. current best has a lot of losses, new child looks better)
                        best = child
                        best_val_NN_scaled = child_NN_scaled_loss_rate
                        best_loss_rate = child_loss_rate


                elif child_NN_scaled_loss_rate == best_val_NN_scaled:  # if both have equal win rate (i.e. both 0/visits),

                    if best_val_NN_scaled == 0: #if both are winners insofar as we know, pick the one with the least visits? (since we're more sure we're doomed with the one visited a lot)
                        if best.visits > child.visits:
                            best = child
                            best_val_NN_scaled = child_NN_scaled_loss_rate
                            best_loss_rate = child_loss_rate
                    else: # get the one with the most visits
                        if best.visits < child.visits:
                            best = child
                            best_val_NN_scaled = child_NN_scaled_loss_rate
                            best_loss_rate = child_loss_rate

    else:
        if non_doomed:
            # no children with value or all doomed
            best, best_val_NN_scaled = get_best_child(node_children, non_doomed=False)
        else:
            # no children with value? happens if search is too slow
            best = random.sample(node_children, 1)[0]
            best_val_NN_scaled = 0
    return best, best_val_NN_scaled

#
# def get_best_children(node_children, game_num):#TODO: make sure to not pick winning children?
#
#     best = choose_best_true_winner(node_children)
#
#
#     # for child in node_children:
#     #     net_wins = child.wins_down_this_tree - child.losses_down_this_tree
#     #     if net_wins > 0:
#     #         best_nodes.append(child)
#     #
#     # if len(best_nodes) > 0:
#     #     best_net_wins = best_nodes[0].wins_down_this_tree - best_nodes[0].losses_down_this_tree
#     #     best = best_nodes[0]
#     #
#     #     for potential_winner in best_nodes: #get best
#     #         num_true_wins = potential_winner.wins_down_this_tree - potential_winner.losses_down_this_tree
#     #         if num_true_wins > best_net_wins:
#     #             best_net_wins = num_true_wins
#     #             best = potential_winner
#     #
#     #
#     #     for potential_winner in best_nodes: #find another best with a higher win-rate
#     #         num_true_wins = potential_winner.wins_down_this_tree - potential_winner.losses_down_this_tree
#     #         if num_true_wins == best_net_wins and \
#     #                 ((potential_winner.visits - potential_winner.wins) / potential_winner.visits) >= ((best.visits - best.wins)/best.visits):
#     #             best = potential_winner
#     #     best_nodes = [best]#return the kid to check.
#
#
#     if best is None:
#         best, best_val = get_best_non_doomed_child(node_children, game_num)
#         scaling_handicap = 1/4#+(game_num/100) #TODO: increase as a function of game_num? more games => stronger scaling strength since we can more safely ignore NN predictions?
#         # best, best_val = get_best_most_visited_child(node_children)
#         best_nodes = []
#         for child in node_children:  # find equally best children
#
#             NN_scaling_factor = 1# ((child.UCT_multiplier-1)/scaling_handicap)+1 #scale the probability
#
#
#             if not child.win_status == True:  # only consider children who will not lead to a win for opponent
#                 if child.visits > 0:
#                     child_loss_rate = ((child.visits - child.wins) / child.visits)
#                     child_NN_scaled__win_rate = NN_scaling_factor * child_loss_rate
#                     # probability = (child.UCT_multiplier-1)
#                     # child_NN_scaled__win_rate = (probability + child_loss_rate)/(1+probability)
#
#                     if child_NN_scaled__win_rate == best_val:
#                         if best.visits == child.visits:
#                             best_nodes.append(child)
#                             # should now have list of equally best children
#         if len(best_nodes) == 0:  # all children are winners => checkmated, just make the best move you have
#             best_nodes.append(best)
#     else:
#         best_nodes = [best]
#     return best_nodes
# def get_best_child(node_children, game_num):
#     scaling_handicap = 1/4#+(game_num/100)
#     overwhelming_amount = 65536
#     k = 0
#     while k < len(node_children)and node_children[k].visits <= 0 :
#         k += 1
#     if k < len(node_children):
#         best = node_children[k]
#         NN_scaling_factor = 1# ((node_children[k].UCT_multiplier-1)/scaling_handicap)+1
#         best_loss_rate = ((node_children[k].visits - node_children[k].wins) / node_children[k].visits)
#
#         best_val_NN_scaled = NN_scaling_factor * best_loss_rate
#
#         # probability = node_children[k].UCT_multiplier-1
#         # best_val_NN_scaled = (probability+ best_loss_rate)/(1+probability)
#
#         for i in range(k, len(node_children)):  # find best child
#             child = node_children[i]
#             NN_scaling_factor = 1#((child.UCT_multiplier-1)/scaling_handicap)+1
#
#             if child.visits > 0:
#                 child_loss_rate = (child.visits - child.wins) / child.visits
#                 child_NN_scaled_loss_rate = NN_scaling_factor * child_loss_rate
#
#
#
#                 # probability = (child.UCT_multiplier-1)
#                 # child_NN_scaled_loss_rate = (child_loss_rate + probability) / (1+probability)
#
#                 if child_NN_scaled_loss_rate > best_val_NN_scaled:  # get the child with the highest loss_init rate
#                     # # and (child.visits / best.visits > 0.3) or best_loss_rate < .5)
#                     if (best.visits >= overwhelming_amount and child.visits >= overwhelming_amount)or \
#                         (best.visits < overwhelming_amount and child.visits >= overwhelming_amount) or \
#                         (best.visits < overwhelming_amount and child.visits < overwhelming_amount) or \
#                         ((best_loss_rate) < .30):
#                             # if both have searched to game overs, (best case # 1)
#                         # if neither have searched to game overs,
#                         # if new child has searched to a gameover and current best hasn't (best case # 2)
#                         # if new child hasn't searched to a gameover, best has, but new child has a better loss_init-rate (i.e. current best has a lot of losses, new child looks better)
#                         best = child
#                         best_val_NN_scaled = child_NN_scaled_loss_rate
#                         best_loss_rate = (best.visits - best.wins) / best.visits
#
#
#                 elif child_NN_scaled_loss_rate == best_val_NN_scaled:  # if both have equal win rate (i.e. both 0/visits),
#
#                     if best_val_NN_scaled == 0: #if both are winners insofar as we know, pick the one with the least visits? (since we're more sure we're doomed with the one visited a lot)
#                         if best.visits > child.visits:
#                             best = child
#                             best_val_NN_scaled = child_NN_scaled_loss_rate
#                             best_loss_rate = (best.visits - best.wins) / best.visits
#                     else: # get the one with the most visits
#                         if best.visits < child.visits:
#                             best = child
#                             best_val_NN_scaled = child_NN_scaled_loss_rate
#                             best_loss_rate = (best.visits - best.wins) / best.visits
#
#     else:
#         # no children with value? happens if search is too slow
#         best = random.sample(node_children, 1)[0]
#         best_val_NN_scaled = 0
#     return best, best_val_NN_scaled
#
# def get_best_non_doomed_child(node_children, game_num):
#     scaling_handicap = 1/4#+(game_num/100)
#     overwhelming_amount = 65536
#     k = 0
#     while k < len(node_children) and (node_children[k].visits <= 0 or node_children[k].win_status is True) :
#         k += 1
#     if k < len(node_children):
#         best = node_children[k]
#         NN_scaling_factor = 1# ((node_children[k].UCT_multiplier-1)/scaling_handicap)+1
#         best_loss_rate = ((node_children[k].visits - node_children[k].wins) / node_children[k].visits)
#
#         best_val_NN_scaled = NN_scaling_factor * best_loss_rate
#
#         # probability = node_children[k].UCT_multiplier-1
#         # best_val_NN_scaled = (probability+ best_loss_rate)/(1+probability)
#
#         for i in range(k, len(node_children)):  # find best child
#             child = node_children[i]
#             NN_scaling_factor = 1#((child.UCT_multiplier-1)/scaling_handicap)+1
#
#             if child.visits > 0 and not child.win_status is True: #only consider non-doomed moves
#                 child_loss_rate = (child.visits - child.wins) / child.visits
#                 child_NN_scaled_loss_rate = NN_scaling_factor * child_loss_rate
#
#
#
#                 # probability = (child.UCT_multiplier-1)
#                 # child_NN_scaled_loss_rate = (child_loss_rate + probability) / (1+probability)
#
#                 if child_NN_scaled_loss_rate > best_val_NN_scaled:  # get the child with the highest loss_init rate
#                     # # and (child.visits / best.visits > 0.3) or best_loss_rate < .5)
#                     if (best.visits >= overwhelming_amount and child.visits >= overwhelming_amount)or \
#                         (best.visits < overwhelming_amount and child.visits >= overwhelming_amount) or \
#                         (best.visits < overwhelming_amount and child.visits < overwhelming_amount) or \
#                         ((best_loss_rate) < .30):
#                         # if both have searched to game overs, (best case # 1)
#                         # if neither have searched to game overs,
#                         # if new child has searched to a gameover and current best hasn't (best case # 2)
#                         # if new child hasn't searched to a gameover, best has, but new child has a better loss_init-rate (i.e. current best has a lot of losses, new child looks better)
#                         best = child
#                         best_val_NN_scaled = child_NN_scaled_loss_rate
#                         best_loss_rate = (best.visits - best.wins) / best.visits
#
#
#                 elif child_NN_scaled_loss_rate == best_val_NN_scaled:  # if both have equal win rate (i.e. both 0/visits),
#
#                     if best_val_NN_scaled == 0: #if both are winners insofar as we know, pick the one with the least visits? (since we're more sure we're doomed with the one visited a lot)
#                         if best.visits > child.visits:
#                             best = child
#                             best_val_NN_scaled = child_NN_scaled_loss_rate
#                             best_loss_rate = (best.visits - best.wins) / best.visits
#                     else: # get the one with the most visits
#                         if best.visits < child.visits:
#                             best = child
#                             best_val_NN_scaled = child_NN_scaled_loss_rate
#                             best_loss_rate = (best.visits - best.wins) / best.visits
#
#     else:
#         # no children with value or all doomed
#         best, best_val_NN_scaled = get_best_child(node_children, game_num)
#     return best, best_val_NN_scaled

def get_best_most_visited_child(node_children):
    k = 0
    threshold_kids = []
    best = None
    best_visits = 0
    best_val = 100
    sorted_by_visit_count = sorted(node_children, key=lambda x: x.visits, reverse=True)
    for child in sorted_by_visit_count:
        if best is not None:
            if child.visits > 0:
                child_win_rate = child.wins / child.visits
                if best_visits == 0:
                    visit_ratio = 1
                    visit_difference = 0
                else:
                    visit_ratio = child.visits/sorted_by_visit_count[0].visits #should always be 1 or less than since we are walking down sorted array
                    visit_difference = abs(best_visits-child.visits)
                if child_win_rate < best_val and (visit_ratio > .5 or best_val > .5) and child_win_rate < .50:#Should be fine since the huge gameover values will make this ratio small compared to trees with no gameover values
                    best = child
                    best_val = child_win_rate
                    best_visits = child.visits
        else:
            best = child
            if child.visits > 0:
                child_win_rate = child.wins / child.visits
                best_val = child_win_rate
            best_visits = child.visits
    if best is None:
        best = random.sample(node_children, 1)[0]
        best_val = 0
    return best, best_val


def random_eval(node):
    amount = 1  # increase to pretend to outweigh NN?
    win = random.randint(0, 1)
    if win == 1:
        update_tree_wins(node, amount)
    else:
        update_tree_losses(node, amount)

def random_rollout(node):
    move = node
    while move.children is not None:
        move = random.sample(move.children, 1)[0]
    outcome, result = evaluation_function(move)
    if outcome == 0:
        update_tree_losses(move, 1)
    else:
        update_tree_wins(move, 1)
    return result

def rollout(node_to_update, descendant_to_eval):
    outcome, _ = evaluation_function(descendant_to_eval)
    descendant_to_eval.rolled_out_from = True
    if outcome == 1:
        if node_to_update.color == descendant_to_eval.color: #future board where I am mover
            update_tree_wins(node_to_update)
        else:
            update_tree_losses(node_to_update)
    elif outcome == 0:#loss_init
        if node_to_update.color == descendant_to_eval.color: #future board where I am mover
            update_tree_losses(node_to_update)
        else:
            update_tree_wins(node_to_update)

def evaluation_function(root):
    # row 2:
    # if white piece or (?) no diagonal black pieces in row 3
    weighted_board = {  #50%
        8: {'a': 24, 'b': 24, 'c': 24, 'd': 24, 'e': 24, 'f': 24, 'g': 24, 'h': 24},
        7: {'a': 21, 'b': 23, 'c': 23, 'd': 23, 'e': 23, 'f': 23, 'g': 23, 'h': 21},
        6: {'a': 14, 'b': 22, 'c': 22, 'd': 22, 'e': 22, 'f': 22, 'g': 22, 'h': 14},
        5: {'a': 9, 'b': 15, 'c': 21, 'd': 21, 'e': 21, 'f': 21, 'g': 15, 'h': 9},
        4: {'a': 6, 'b': 9, 'c': 16, 'd': 16, 'e': 16, 'f': 16, 'g': 9, 'h': 6},
        3: {'a': 3, 'b': 5, 'c': 10, 'd': 10, 'e': 10, 'f': 10, 'g': 5, 'h': 3},
        2: {'a': 2, 'b': 3, 'c': 3, 'd': 3, 'e': 3, 'f': 3, 'g': 3, 'h': 2},
        1: {'a': 5, 'b': 28, 'c': 28, 'd': 12, 'e': 12, 'f': 28, 'g': 28, 'h': 5}
    }
    white = 'w'
    black = 'b'
    is_white_index = 9
    white_move_index = 10
    player_color = root.color
    opponent_dict = { 'White': 'Black',
             'Black': 'White'

    }
    win_weight = 0
    result = 0
    for row in root.game_board:
        if row != is_white_index and row != white_move_index:  # don't touch these indexes
            for col in root.game_board[row]:
                if root.game_board[row][col] == white:
                # if row == 2:
                #     if col == player_color:
                #         win_weight += 1
                #     if
                    result += weighted_board[row][col]
                elif root.game_board[row][col] == black:
                    result -= weighted_board[9-row][col]
    # print(result)
    max_result_can_be = 141
    max_result_can_be = max_result_can_be/1.5
    if result > 0:
        if player_color == 'White':
            outcome = 1
            result = result / max(max_result_can_be, result)
        else:
            outcome =  0
            result = 1 - (result / max(max_result_can_be, result))

    else:
        if player_color == 'Black':
            outcome = 1
            result = abs(result / max(max_result_can_be, result))

        else:
            outcome = 0
            result = 1 - abs(result / max(max_result_can_be, result))
    return outcome, result

def update_values_from_policy_net(game_tree, policy_net, lock = None, pruning=False): #takes in a list of parents with children,
    # removes children who were guaranteed losses for parent (should be fine as guaranteed loss_init info already backpropagated)
    # can also prune for not in top NN, but EBFS MCTS with depth_limit = 1 will also do that
    NN_output = policy_net.evaluate(game_tree)
    # if lock is None: #make a useless lock so we can have clean code either way
    #     lock = threading.Lock()
    with lock:
        for i in range(0, len(NN_output)):
            top_children_indexes = get_top_children(NN_output[i], num_top=5)#TODO: play with this number
            parent = game_tree[i]
            sum_for_normalization = update_sum_for_normalization(parent, NN_output, top_children_indexes)
            if parent.children is not None:
                pruned_children = []
                for child in parent.children:#iterate to update values
                    normalized_value = (NN_output[child.index] / sum_for_normalization) * 100
                    if child.gameover is False and normalized_value > 0:# update only if not the end of the game or a reasonable value
                        if child.index in top_children_indexes: #prune
                            pruned_children.append(child)
                            update_child(child, NN_output[i], top_children_indexes)
                        elif not pruning:#if unknown and not pruning, keep
                            pruned_children.append(child)
                            update_child(child, NN_output[i], top_children_indexes)
                    elif child.win_status is not None: #if win/loss_init for parent, keep
                            pruned_children.append(child)
                        #no need to update child. if it has a win status, either it was expanded or was an instant game over
                parent.children = pruned_children


# def update_value_from_policy_net_async(game_tree, lock, policy_net, thread = None, pruning=False): #takes in a list of parents with children,
#     # removes children who were guaranteed losses for parent (should be fine as guaranteed loss_init info already backpropagated))
#     # can also prune for not in top NN, but EBFS MCTS with depth_limit = 1 will also do tha
#     # NN_processing = False
#
#     #TODO: figure out if this even needs thread local storage since threads enter separate function calls?
#
#     if thread is None:
#         thread = threading.local()
#     with lock:
#         thread.game_tree = game_tree
#     thread.NN_output = policy_net.evaluate(thread.game_tree)
#
#     #TODO: test thread safety without lock using local variables
#     thread.parent_index = 0
#     # with lock:
#     while thread.parent_index < len(thread.NN_output): #batch of nodes unique to thread in block
#         thread.pruned_children = []
#         thread.top_children_indexes = get_top_children(thread.NN_output[thread.parent_index], num_top=5)#TODO: play with this number
#         thread.parent = thread.game_tree[thread.parent_index]
#         if thread.parent.children is not None:
#             thread.child_index = 0
#             while thread.child_index < len(thread.parent.children):
#                 thread.child = thread.parent.children[thread.child_index]
#                 if thread.child.index in thread.top_children_indexes:
#                     thread.pruned_children.append(thread.child)
#                     if thread.child.gameover is False:  # update only if not the end of the game
#                         with lock:
#                             update_child(thread.child, thread.NN_output[thread.parent_index], thread.top_children_indexes)
#                 elif thread.child.win_status is not None: #if win/loss_init for thread.parent, keep
#                     thread.pruned_children.append(thread.child)
#                     #no need to update child. if it has a win status, either it was expanded or was an instant game over
#                 elif pruning:
#                     subtract_child_wins_and_visits(thread.parent, thread.child)
#                 elif not pruning:#if unknown and not pruning, keep non-top child
#                     if thread.child.gameover is False:
#                         with lock:
#                             update_child(thread.child, thread.NN_output[thread.parent_index], thread.top_children_indexes)
#                     thread.pruned_children.append(thread.child)
#                 thread.child_index += 1
#         thread.parent.children = thread.pruned_children
#         thread.parent_index += 1

def update_child(child, NN_output, top_children_indexes, num_legal_children, sim_info):
    child_val = NN_output[child.index]

    # if top_children_indexes[0] == child.index:  # rank 1 child
    #     child.parent.best_child = child  # mark as node to expand first
    # child_val *= 2
    #     if child_val >= .90:
    #         child_val =1.5
    #     else:
    #         if child_val > .20:
    #             child_val = max(child_val, .491780905081678)  # sometimes it gets under confident
    # elif top_children_indexes[1] == child.index:
    #     child_val = max(child_val, .18969851788510255)
    # elif top_children_indexes[2] == child.index:
    #     child_val = max(child_val, .10004993248995586)
    # elif top_children_indexes[3] == child.index:
    #     child_val = max(child_val, .05907234751883528)
    # elif top_children_indexes[4] == child.index:
    #     child_val = max(child_val, .036425774953655967)
    # elif top_children_indexes[5] == child.index:
    #     child_val = max(child_val, .024950243991511947)
    # elif top_children_indexes[6] == child.index:
    #     child_val = max(child_val, .017902280093502234)
    # elif top_children_indexes[7] == child.index:
    #     child_val = max(child_val, .013378707110885424)
    # elif top_children_indexes[8] == child.index:
    #     child_val = max(child_val, .010220394763159517)
    # elif top_children_indexes[9] == child.index:
    #     child_val = max(child_val, .008041201598780913)

    normalized_value = int(child_val * 100)

    # TODO: 03/15/2017 removed based on prof Lorentz input
    # if child.color == 'Black':
    #     child.UCT_multiplier  = 1 + (child_val*2)# stay close to policy (net) trajectory by biasing UCT selection of
    #                                      # NN's top picks as a function of probability returned by NN
    # else:
    #     child.UCT_multiplier = 1 + (child_val)  # stay close to policy (net) trajectory by biasing UCT selection of
    #     # NN's top picks as a function of probability returned by NN

    child.UCT_multiplier = 1 + (child_val)  # stay close to policy (net) trajectory by biasing UCT selection of
    # NN's top picks as a function of probability returned by NN

    # TODO: 03/11/2017 7:45 AM added this to do simulated random rollouts instead of assuming all losses
    # i.e. if policy chooses child with 30% probability => 30/100 games
    # => randomly decide which of those 30 games are wins and which are losses

    # TODO: 03/15/2017 based on Prof Lorentz input, wins/visits = NNprob/100
    prior_value_multiplier = 1
    weighted_losses = normalized_value * prior_value_multiplier
    child.visits = 100 * prior_value_multiplier
    # weighted_wins = (child.visits-weighted_losses)
    weighted_wins = ((
                     child.visits - weighted_losses) ) #/ child.visits  # may be a negative number if we are increasing probability ** 2
    child.wins = weighted_wins

    # update_tree_wins(child, weighted_wins)
    # update_tree_losses(child, weighted_losses)

    #  num_top_to_consider = max(1, int(num_legal_children/2.5))
    #  top_n_to_consider = top_children_indexes[:num_top_to_consider]
    #  num_winners = max(1, int(num_top_to_consider/2))
    #  num_losers = min (num_winners, num_top_to_consider)
    #  top_n_winners = top_children_indexes[:num_winners]
    #  top_n_losers = top_children_indexes[num_winners:num_losers]
    #
    #  #TODO: 03232017 based on prof lorentz input, only backprop a single win/loss_init value
    # #01_03242017move_EBFS MCTSvsWandererdepth1_ttt10Annealing_Multiplier_BackpropOnlyTopKids_singleDL is using this + predicate!
    #  if child.index in top_n_winners:
    #      update_tree_wins(child.parent, 1)
    #  elif child.index in top_n_losers:
    #      update_tree_losses(child.parent, 1)

    # if child.index in top_n_to_consider:
    # outcome, _ = evaluation_function(child)
    # if outcome == 1:
    #     update_tree_losses(child.parent)
    # else:
    #     if child_val> .90:
    #         amount = 1
    #     else:
    #         amount = 1
    #     update_tree_wins(child.parent, amount)

    # if child_val > .30:
    #     update_tree_wins(child.parent)
    # else:
    #     update_tree_losses(child.parent)
    # if child.height >= 60:
    # random_prob = random.random()
    random_prob = 1
    if sim_info.do_eval:
        rollout_and_eval_if_parent_at_depth(child, 1)  # since only called child initialization, inner check redundant


        # child.visits = normalized_value
        # child.wins = normalized_value * random_rollout(child)
        # assert (child.visits >= child.wins)
def random_to_depth_rollout(parent_to_update, depth=0): #bad because will not find every depth d child
    descendant_to_eval = parent_to_update #this turns into child to rollout
    descendant_exists = True
    while depth > 0 and descendant_exists:
        if descendant_to_eval.children is not None:
            candidates = list(filter(lambda x: x.depth == depth, descendant_to_eval.children))
            descendant_to_eval = random.sample(candidates, 1)[0]  # more MCTS-y.
            depth -=1
        else:
            descendant_exists = False
    if depth == 0 and not descendant_to_eval.rolled_out_from:
        rollout(parent_to_update, descendant_to_eval)

 #TODO: better to keep track of subtree height so we can randomly rollout which of the subtrees we know has depth d?

def rollout_and_eval_if_parent_at_depth(descendant_to_eval, depth = 0): #bad because will find every depth d child
    parent_to_update = descendant_to_eval #this turns into parent to update
    parent_exists = True
    while depth > 0 and parent_exists:
        if parent_to_update.parent is not None:
            parent_to_update = parent_to_update.parent
            depth -=1
        else:
            parent_exists = False
    if depth == 0 and not descendant_to_eval.rolled_out_from:
        rollout(parent_to_update, descendant_to_eval)
def eval_child(child):
    if child.height < 47:  # pre-rollout
        outcome, _ = evaluation_function(child)
        if outcome == 1:
            update_tree_losses(child.parent)
        else:
            update_tree_wins(child.parent)

def update_sum_for_normalization(parent, NN_output, child_indexes):
    #if we want to normalize over legal/top children vs relying on NN's softmax
    if parent.sum_for_children_normalization is None:
        parent.sum_for_children_normalization = sum(map(lambda child_index:
                                    NN_output[child_index],
                                                        child_indexes))
    return parent.sum_for_children_normalization

#returns a sorted list (best to worst as evaluated by the NN) of the children as move indexes
def get_top_children(NN_output, num_top=0):

    if num_top == 0:
        num_top = len(NN_output)
        full_sort = NN_output.argsort()[::-1][:num_top]
    else:
        partial_sort = argpartition(NN_output, NN_output.size-num_top+1)[-num_top:]
        full_sort = partial_sort[NN_output[partial_sort].argsort()][::-1]
    return full_sort