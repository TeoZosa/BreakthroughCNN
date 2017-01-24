import os
import fnmatch
import sys

def find_files(path, extension):  # recursively find files at path with extension; pulled from StackOverflow
    for root, dirs, files in os.walk(path):
        for file in fnmatch.filter(files, extension):
            yield os.path.join(root, file)
            
def batch_split(inputs, labels, batch_size):
    # lazily split into training batches of size batch_size
    X_train_batches = [inputs[:batch_size]]
    y_train_batches = [labels[:batch_size]]
    remaining_x_train = inputs[batch_size:]
    remaining_y_train = labels[batch_size:]
    for i in range(1, len(inputs) // batch_size):
        X_train_batches.append(remaining_x_train[:batch_size])
        y_train_batches.append(remaining_y_train[:batch_size])
        remaining_x_train = remaining_x_train[batch_size:]
        remaining_y_train = remaining_y_train[batch_size:]
    X_train_batches.append(remaining_x_train)  # append remaining training examples
    y_train_batches.append(remaining_y_train)
    return X_train_batches, y_train_batches

def move_lookup(index, player_color):
    # Enumerated the moves for lookup speed/visual reference (see commented out dictionary).
    # Code can be prettified by calling generate_move_lookup instead
    if player_color.lower() == 'White'.lower():
        transitions = [
                     'a1-a2',
                     'a1-b2',
                     'b1-a2',
                     'b1-b2',
                     'b1-c2',
                     'c1-b2',
                     'c1-c2',
                     'c1-d2',
                     'd1-c2',
                     'd1-d2',
                     'd1-e2',
                     'e1-d2',
                     'e1-e2',
                     'e1-f2',
                     'f1-e2',
                     'f1-f2',
                     'f1-g2',
                     'g1-f2',
                     'g1-g2',
                     'g1-h2',
                     'h1-g2',
                     'h1-h2',
                     'a2-a3',
                     'a2-b3',
                     'b2-a3',
                     'b2-b3',
                     'b2-c3',
                     'c2-b3',
                     'c2-c3',
                     'c2-d3',
                     'd2-c3',
                     'd2-d3',
                     'd2-e3',
                     'e2-d3',
                     'e2-e3',
                     'e2-f3',
                     'f2-e3',
                     'f2-f3',
                     'f2-g3',
                     'g2-f3',
                     'g2-g3',
                     'g2-h3',
                     'h2-g3',
                     'h2-h3',
                     'a3-a4',
                     'a3-b4',
                     'b3-a4',
                     'b3-b4',
                     'b3-c4',
                     'c3-b4',
                     'c3-c4',
                     'c3-d4',
                     'd3-c4',
                     'd3-d4',
                     'd3-e4',
                     'e3-d4',
                     'e3-e4',
                     'e3-f4',
                     'f3-e4',
                     'f3-f4',
                     'f3-g4',
                     'g3-f4',
                     'g3-g4',
                     'g3-h4',
                     'h3-g4',
                     'h3-h4',
                     'a4-a5',
                     'a4-b5',
                     'b4-a5',
                     'b4-b5',
                     'b4-c5',
                     'c4-b5',
                     'c4-c5',
                     'c4-d5',
                     'd4-c5',
                     'd4-d5',
                     'd4-e5',
                     'e4-d5',
                     'e4-e5',
                     'e4-f5',
                     'f4-e5',
                     'f4-f5',
                     'f4-g5',
                     'g4-f5',
                     'g4-g5',
                     'g4-h5',
                     'h4-g5',
                     'h4-h5',
                     'a5-a6',
                     'a5-b6',
                     'b5-a6',
                     'b5-b6',
                     'b5-c6',
                     'c5-b6',
                     'c5-c6',
                     'c5-d6',
                     'd5-c6',
                     'd5-d6',
                     'd5-e6',
                     'e5-d6',
                     'e5-e6',
                     'e5-f6',
                     'f5-e6',
                     'f5-f6',
                     'f5-g6',
                     'g5-f6',
                     'g5-g6',
                     'g5-h6',
                     'h5-g6',
                     'h5-h6',
                     'a6-a7',
                     'a6-b7',
                     'b6-a7',
                     'b6-b7',
                     'b6-c7',
                     'c6-b7',
                     'c6-c7',
                     'c6-d7',
                     'd6-c7',
                     'd6-d7',
                     'd6-e7',
                     'e6-d7',
                     'e6-e7',
                     'e6-f7',
                     'f6-e7',
                     'f6-f7',
                     'f6-g7',
                     'g6-f7',
                     'g6-g7',
                     'g6-h7',
                     'h6-g7',
                     'h6-h7',
                     'a7-a8',
                     'a7-b8',
                     'b7-a8',
                     'b7-b8',
                     'b7-c8',
                     'c7-b8',
                     'c7-c8',
                     'c7-d8',
                     'd7-c8',
                     'd7-d8',
                     'd7-e8',
                     'e7-d8',
                     'e7-e8',
                     'e7-f8',
                     'f7-e8',
                     'f7-f8',
                     'f7-g8',
                     'g7-f8',
                     'g7-g8',
                     'g7-h8',
                     'h7-g8',
                     'h7-h8',
                     'no-move']

        # transitions = {0: 'a1-a2',
        #              1: 'a1-b2',
        #              2: 'b1-a2',
        #              3: 'b1-b2',
        #              4: 'b1-c2',
        #              5: 'c1-b2',
        #              6: 'c1-c2',
        #              7: 'c1-d2',
        #              8: 'd1-c2',
        #              9: 'd1-d2',
        #              10: 'd1-e2',
        #              11: 'e1-d2',
        #              12: 'e1-e2',
        #              13: 'e1-f2',
        #              14: 'f1-e2',
        #              15: 'f1-f2',
        #              16: 'f1-g2',
        #              17: 'g1-f2',
        #              18: 'g1-g2',
        #              19: 'g1-h2',
        #              20: 'h1-g2',
        #              21: 'h1-h2',
        #              22: 'a2-a3',
        #              23: 'a2-b3',
        #              24: 'b2-a3',
        #              25: 'b2-b3',
        #              26: 'b2-c3',
        #              27: 'c2-b3',
        #              28: 'c2-c3',
        #              29: 'c2-d3',
        #              30: 'd2-c3',
        #              31: 'd2-d3',
        #              32: 'd2-e3',
        #              33: 'e2-d3',
        #              34: 'e2-e3',
        #              35: 'e2-f3',
        #              36: 'f2-e3',
        #              37: 'f2-f3',
        #              38: 'f2-g3',
        #              39: 'g2-f3',
        #              40: 'g2-g3',
        #              41: 'g2-h3',
        #              42: 'h2-g3',
        #              43: 'h2-h3',
        #              44: 'a3-a4',
        #              45: 'a3-b4',
        #              46: 'b3-a4',
        #              47: 'b3-b4',
        #              48: 'b3-c4',
        #              49: 'c3-b4',
        #              50: 'c3-c4',
        #              51: 'c3-d4',
        #              52: 'd3-c4',
        #              53: 'd3-d4',
        #              54: 'd3-e4',
        #              55: 'e3-d4',
        #              56: 'e3-e4',
        #              57: 'e3-f4',
        #              58: 'f3-e4',
        #              59: 'f3-f4',
        #              60: 'f3-g4',
        #              61: 'g3-f4',
        #              62: 'g3-g4',
        #              63: 'g3-h4',
        #              64: 'h3-g4',
        #              65: 'h3-h4',
        #              66: 'a4-a5',
        #              67: 'a4-b5',
        #              68: 'b4-a5',
        #              69: 'b4-b5',
        #              70: 'b4-c5',
        #              71: 'c4-b5',
        #              72: 'c4-c5',
        #              73: 'c4-d5',
        #              74: 'd4-c5',
        #              75: 'd4-d5',
        #              76: 'd4-e5',
        #              77: 'e4-d5',
        #              78: 'e4-e5',
        #              79: 'e4-f5',
        #              80: 'f4-e5',
        #              81: 'f4-f5',
        #              82: 'f4-g5',
        #              83: 'g4-f5',
        #              84: 'g4-g5',
        #              85: 'g4-h5',
        #              86: 'h4-g5',
        #              87: 'h4-h5',
        #              88: 'a5-a6',
        #              89: 'a5-b6',
        #              90: 'b5-a6',
        #              91: 'b5-b6',
        #              92: 'b5-c6',
        #              93: 'c5-b6',
        #              94: 'c5-c6',
        #              95: 'c5-d6',
        #              96: 'd5-c6',
        #              97: 'd5-d6',
        #              98: 'd5-e6',
        #              99: 'e5-d6',
        #              100: 'e5-e6',
        #              101: 'e5-f6',
        #              102: 'f5-e6',
        #              103: 'f5-f6',
        #              104: 'f5-g6',
        #              105: 'g5-f6',
        #              106: 'g5-g6',
        #              107: 'g5-h6',
        #              108: 'h5-g6',
        #              109: 'h5-h6',
        #              110: 'a6-a7',
        #              111: 'a6-b7',
        #              112: 'b6-a7',
        #              113: 'b6-b7',
        #              114: 'b6-c7',
        #              115: 'c6-b7',
        #              116: 'c6-c7',
        #              117: 'c6-d7',
        #              118: 'd6-c7',
        #              119: 'd6-d7',
        #              120: 'd6-e7',
        #              121: 'e6-d7',
        #              122: 'e6-e7',
        #              123: 'e6-f7',
        #              124: 'f6-e7',
        #              125: 'f6-f7',
        #              126: 'f6-g7',
        #              127: 'g6-f7',
        #              128: 'g6-g7',
        #              129: 'g6-h7',
        #              130: 'h6-g7',
        #              131: 'h6-h7',
        #              132: 'a7-a8',
        #              133: 'a7-b8',
        #              134: 'b7-a8',
        #              135: 'b7-b8',
        #              136: 'b7-c8',
        #              137: 'c7-b8',
        #              138: 'c7-c8',
        #              139: 'c7-d8',
        #              140: 'd7-c8',
        #              141: 'd7-d8',
        #              142: 'd7-e8',
        #              143: 'e7-d8',
        #              144: 'e7-e8',
        #              145: 'e7-f8',
        #              146: 'f7-e8',
        #              147: 'f7-f8',
        #              148: 'f7-g8',
        #              149: 'g7-f8',
        #              150: 'g7-g8',
        #              151: 'g7-h8',
        #              152: 'h7-g8',
        #              153: 'h7-h8',
        #              154: 'no-move'}

    elif player_color.lower() == 'Black'.lower():
        transitions = [
                     'a8-a7',
                     'a8-b7',
                     'b8-a7',
                     'b8-b7',
                     'b8-c7',
                     'c8-b7',
                     'c8-c7',
                     'c8-d7',
                     'd8-c7',
                     'd8-d7',
                     'd8-e7',
                     'e8-d7',
                     'e8-e7',
                     'e8-f7',
                     'f8-e7',
                     'f8-f7',
                     'f8-g7',
                     'g8-f7',
                     'g8-g7',
                     'g8-h7',
                     'h8-g7',
                     'h8-h7',
                     'a7-a6',
                     'a7-b6',
                     'b7-a6',
                     'b7-b6',
                     'b7-c6',
                     'c7-b6',
                     'c7-c6',
                     'c7-d6',
                     'd7-c6',
                     'd7-d6',
                     'd7-e6',
                     'e7-d6',
                     'e7-e6',
                     'e7-f6',
                     'f7-e6',
                     'f7-f6',
                     'f7-g6',
                     'g7-f6',
                     'g7-g6',
                     'g7-h6',
                     'h7-g6',
                     'h7-h6',
                     'a6-a5',
                     'a6-b5',
                     'b6-a5',
                     'b6-b5',
                     'b6-c5',
                     'c6-b5',
                     'c6-c5',
                     'c6-d5',
                     'd6-c5',
                     'd6-d5',
                     'd6-e5',
                     'e6-d5',
                     'e6-e5',
                     'e6-f5',
                     'f6-e5',
                     'f6-f5',
                     'f6-g5',
                     'g6-f5',
                     'g6-g5',
                     'g6-h5',
                     'h6-g5',
                     'h6-h5',
                     'a5-a4',
                     'a5-b4',
                     'b5-a4',
                     'b5-b4',
                     'b5-c4',
                     'c5-b4',
                     'c5-c4',
                     'c5-d4',
                     'd5-c4',
                     'd5-d4',
                     'd5-e4',
                     'e5-d4',
                     'e5-e4',
                     'e5-f4',
                     'f5-e4',
                     'f5-f4',
                     'f5-g4',
                     'g5-f4',
                     'g5-g4',
                     'g5-h4',
                     'h5-g4',
                     'h5-h4',
                     'a4-a3',
                     'a4-b3',
                     'b4-a3',
                     'b4-b3',
                     'b4-c3',
                     'c4-b3',
                     'c4-c3',
                     'c4-d3',
                     'd4-c3',
                     'd4-d3',
                     'd4-e3',
                     'e4-d3',
                     'e4-e3',
                     'e4-f3',
                     'f4-e3',
                     'f4-f3',
                     'f4-g3',
                     'g4-f3',
                     'g4-g3',
                     'g4-h3',
                     'h4-g3',
                     'h4-h3',
                     'a3-a2',
                     'a3-b2',
                     'b3-a2',
                     'b3-b2',
                     'b3-c2',
                     'c3-b2',
                     'c3-c2',
                     'c3-d2',
                     'd3-c2',
                     'd3-d2',
                     'd3-e2',
                     'e3-d2',
                     'e3-e2',
                     'e3-f2',
                     'f3-e2',
                     'f3-f2',
                     'f3-g2',
                     'g3-f2',
                     'g3-g2',
                     'g3-h2',
                     'h3-g2',
                     'h3-h2',
                     'a2-a1',
                     'a2-b1',
                     'b2-a1',
                     'b2-b1',
                     'b2-c1',
                     'c2-b1',
                     'c2-c1',
                     'c2-d1',
                     'd2-c1',
                     'd2-d1',
                     'd2-e1',
                     'e2-d1',
                     'e2-e1',
                     'e2-f1',
                     'f2-e1',
                     'f2-f1',
                     'f2-g1',
                     'g2-f1',
                     'g2-g1',
                     'g2-h1',
                     'h2-g1',
                     'h2-h1',
                     'no-move']

        # transitions = {0: 'a8-a7',
        #              1: 'a8-b7',
        #              2: 'b8-a7',
        #              3: 'b8-b7',
        #              4: 'b8-c7',
        #              5: 'c8-b7',
        #              6: 'c8-c7',
        #              7: 'c8-d7',
        #              8: 'd8-c7',
        #              9: 'd8-d7',
        #              10: 'd8-e7',
        #              11: 'e8-d7',
        #              12: 'e8-e7',
        #              13: 'e8-f7',
        #              14: 'f8-e7',
        #              15: 'f8-f7',
        #              16: 'f8-g7',
        #              17: 'g8-f7',
        #              18: 'g8-g7',
        #              19: 'g8-h7',
        #              20: 'h8-g7',
        #              21: 'h8-h7',
        #              22: 'a7-a6',
        #              23: 'a7-b6',
        #              24: 'b7-a6',
        #              25: 'b7-b6',
        #              26: 'b7-c6',
        #              27: 'c7-b6',
        #              28: 'c7-c6',
        #              29: 'c7-d6',
        #              30: 'd7-c6',
        #              31: 'd7-d6',
        #              32: 'd7-e6',
        #              33: 'e7-d6',
        #              34: 'e7-e6',
        #              35: 'e7-f6',
        #              36: 'f7-e6',
        #              37: 'f7-f6',
        #              38: 'f7-g6',
        #              39: 'g7-f6',
        #              40: 'g7-g6',
        #              41: 'g7-h6',
        #              42: 'h7-g6',
        #              43: 'h7-h6',
        #              44: 'a6-a5',
        #              45: 'a6-b5',
        #              46: 'b6-a5',
        #              47: 'b6-b5',
        #              48: 'b6-c5',
        #              49: 'c6-b5',
        #              50: 'c6-c5',
        #              51: 'c6-d5',
        #              52: 'd6-c5',
        #              53: 'd6-d5',
        #              54: 'd6-e5',
        #              55: 'e6-d5',
        #              56: 'e6-e5',
        #              57: 'e6-f5',
        #              58: 'f6-e5',
        #              59: 'f6-f5',
        #              60: 'f6-g5',
        #              61: 'g6-f5',
        #              62: 'g6-g5',
        #              63: 'g6-h5',
        #              64: 'h6-g5',
        #              65: 'h6-h5',
        #              66: 'a5-a4',
        #              67: 'a5-b4',
        #              68: 'b5-a4',
        #              69: 'b5-b4',
        #              70: 'b5-c4',
        #              71: 'c5-b4',
        #              72: 'c5-c4',
        #              73: 'c5-d4',
        #              74: 'd5-c4',
        #              75: 'd5-d4',
        #              76: 'd5-e4',
        #              77: 'e5-d4',
        #              78: 'e5-e4',
        #              79: 'e5-f4',
        #              80: 'f5-e4',
        #              81: 'f5-f4',
        #              82: 'f5-g4',
        #              83: 'g5-f4',
        #              84: 'g5-g4',
        #              85: 'g5-h4',
        #              86: 'h5-g4',
        #              87: 'h5-h4',
        #              88: 'a4-a3',
        #              89: 'a4-b3',
        #              90: 'b4-a3',
        #              91: 'b4-b3',
        #              92: 'b4-c3',
        #              93: 'c4-b3',
        #              94: 'c4-c3',
        #              95: 'c4-d3',
        #              96: 'd4-c3',
        #              97: 'd4-d3',
        #              98: 'd4-e3',
        #              99: 'e4-d3',
        #              100: 'e4-e3',
        #              101: 'e4-f3',
        #              102: 'f4-e3',
        #              103: 'f4-f3',
        #              104: 'f4-g3',
        #              105: 'g4-f3',
        #              106: 'g4-g3',
        #              107: 'g4-h3',
        #              108: 'h4-g3',
        #              109: 'h4-h3',
        #              110: 'a3-a2',
        #              111: 'a3-b2',
        #              112: 'b3-a2',
        #              113: 'b3-b2',
        #              114: 'b3-c2',
        #              115: 'c3-b2',
        #              116: 'c3-c2',
        #              117: 'c3-d2',
        #              118: 'd3-c2',
        #              119: 'd3-d2',
        #              120: 'd3-e2',
        #              121: 'e3-d2',
        #              122: 'e3-e2',
        #              123: 'e3-f2',
        #              124: 'f3-e2',
        #              125: 'f3-f2',
        #              126: 'f3-g2',
        #              127: 'g3-f2',
        #              128: 'g3-g2',
        #              129: 'g3-h2',
        #              130: 'h3-g2',
        #              131: 'h3-h2',
        #              132: 'a2-a1',
        #              133: 'a2-b1',
        #              134: 'b2-a1',
        #              135: 'b2-b1',
        #              136: 'b2-c1',
        #              137: 'c2-b1',
        #              138: 'c2-c1',
        #              139: 'c2-d1',
        #              140: 'd2-c1',
        #              141: 'd2-d1',
        #              142: 'd2-e1',
        #              143: 'e2-d1',
        #              144: 'e2-e1',
        #              145: 'e2-f1',
        #              146: 'f2-e1',
        #              147: 'f2-f1',
        #              148: 'f2-g1',
        #              149: 'g2-f1',
        #              150: 'g2-g1',
        #              151: 'g2-h1',
        #              152: 'h2-g1',
        #              153: 'h2-h1',
        #              154: 'no-move'}
    else:
        transitions = []
        print("ERROR: Please specify a valid player color", file=sys.stderr)
        exit(10)
    return transitions[index]


def generate_move_lookup():
    chars = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
    white_transitions = []
    for k in range (1, 9): #white's moves
        if k != 8:
            for i in range(0, len(chars)):
                if i == 0:
                    white_transitions.append(chars[i]+str(k)+'-'+chars[i]+str(k+1))
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i+1] + str(k + 1))
                elif i == len(chars)-1:
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i-1] + str(k + 1))
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i] + str(k + 1))
                else:
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i - 1] + str(k + 1))
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i] + str(k + 1))
                    white_transitions.append(chars[i] + str(k) + '-' + chars[i+1] + str(k + 1))
    black_transitions = []
    for k in range (8, 0, -1): #black's moves
        if k != 1:
            for i in range(0, len(chars)):
                if i == 0:
                    black_transitions.append(chars[i]+str(k)+'-'+chars[i]+str(k-1))
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i+1] + str(k - 1))
                elif i == len(chars)-1:
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i-1] + str(k - 1))
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i] + str(k - 1))
                else:
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i - 1] + str(k - 1))
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i] + str(k - 1))
                    black_transitions.append(chars[i] + str(k) + '-' + chars[i+1] + str(k - 1))
    white_transitions.append('no-move')
    black_transitions.append('no-move')
    # return dict(enumerate(white_transitions)), dict(enumerate(black_transitions))
    return white_transitions, black_transitions