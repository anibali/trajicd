module trajic.minihuff;

import trajic.stream;

import std.algorithm;
import std.typecons;
import std.range;
import std.string;
import std.stream;
import std.conv: to;
import std.container: heapify;

import std.stdio;

// Minihuff - super compact huffman representation where symbols must
// be in the non-negative range of a signed integer

template IsSignedInteger(T) {
  enum IsSignedInteger =
    __traits(isIntegral, T) && !__traits(isUnsigned, T);
}

auto createMinihuff(S)(double[S] frequencyMap) if(IsSignedInteger!S)
in {
  double totalFrequency = 0;
  foreach(symbol, frequency; frequencyMap) {
    assert(symbol >= 0);
    totalFrequency += frequency;
  }
  assert((totalFrequency - 1) < 0.001);
} body {
  alias Pair = Tuple!(S, "symbol", string, "code");
  alias Block = Tuple!(double, "frequency", Pair[], "pairs");

  Block[] blocks;
  foreach(symbol, frequency; frequencyMap) {
    blocks ~= Block(frequency, [Pair(symbol, "")]);
  }
  // Create min-heap
  auto heap = blocks.heapify!("a > b");

  while (heap.length > 1) {
    Block lo = heap.front(); heap.removeFront();
    Block hi = heap.front(); heap.removeFront();
    foreach(ref pair; lo.pairs)
      pair.code = '0' ~ pair.code;
    foreach(ref pair; hi.pairs)
      pair.code = '1' ~ pair.code;
    // Merge blocks
    heap.insert(Block(lo.frequency + hi.frequency, lo.pairs ~ hi.pairs));
  }

  auto codewords = heap.front().pairs;

  // Make canonical
  codewords.multiSort!(
    "a.code.length < b.code.length",
    "a.symbol < b.symbol",
    SwapStrategy.unstable
  );
  int codeword = -1;
  ulong previousLength = 1;
  foreach(i; 0..codewords.length) {
    ++codeword;
    codeword <<= codewords[i].code.length - previousLength;
    previousLength = codewords[i].code.length;
    codewords[i].code = format("%0"~to!string(previousLength)~"b", codeword);
  }

  return codewords;
}

unittest {
  double[byte] freqMap = ['a': 0.3, 'b': 0.5, 'c': 0.1, 'd': 0.1];

  auto codewords = createMinihuff(freqMap);
  auto codebookMap = codewords.assocArray();
  assert(codebookMap['a'] == "10");
  assert(codebookMap['b'] == "0");
  assert(codebookMap['c'] == "110");
  assert(codebookMap['d'] == "111");
}

auto encodeMinihuff(T)(T[] codewords)
  if(isTuple!T)
out(buffer) {
  assert(buffer.length == codewords.length * 2 - 1);
  // Symbols appear in order, and any node that is not a leaf node
  // (contains a symbol) is a branch (contains negative number)
  ulong index = 0;
  foreach(node; buffer) {
    assert(node < 0 || node == codewords[index++].symbol);
  }
} body {
  static if (is(T : TX!TL, alias TX, TL...)) {
    alias S = TL[0];
    assert(IsSignedInteger!S);

    auto buffer = new S[codewords.length * 2 - 1];

    if(buffer.length == 1) {
      return [codewords[0].symbol];
    }

    string prefix = "";

    S index = 1;
    string previousCode = "X";
    foreach(pair; codewords) {
      // Finished a zero branch
      string commonPrefix = "";
      foreach(i, ch; previousCode) {
        if(pair.code[i] == ch)
          commonPrefix ~= ch;
        else
          break;
      }
      
      S branchIndex = 0;
      foreach(ch; commonPrefix) {
        if(ch == '0') {
          ++branchIndex;
        } else {
          branchIndex = -buffer[branchIndex];
        }
      }
      buffer[branchIndex] = -index;

      string suffix = pair.code.chompPrefix(commonPrefix);
      index += suffix.length - 1;
      buffer[index] = pair.symbol;
      ++index;

      previousCode = pair.code;
    }

    return buffer;
  } else {
    assert(0);
  }
}

unittest {
  double[byte] freqMap = ['w': 0.25, 'x': 0.25, 'y': 0.25, 'z': 0.25];
  auto codebook = encodeMinihuff(createMinihuff(freqMap));
  assert(codebook == [-4, -3, 'w', 'x', -6, 'y', 'z']);
}

auto readMinihuff(S)(InputStream instream) if(IsSignedInteger!S)
{
  S[] codebook;
  int nextOneBranch = 0;
  int i = 0;

  do {
    S node;
    instream.read(node);

    if(i == nextOneBranch) {
      nextOneBranch = -node;
    }

    codebook ~= node;
    ++i;
  } while(nextOneBranch > -1);

  return codebook;
}

auto lookupMinihuff(S, R)(S[] codebook, ref R range)
  if(IsSignedInteger!S && isInputRange!R && is(ElementType!R == bool))
{
  auto currentNode = codebook[0];
  auto currentNodeIndex = 0;
  while(currentNode < 0) {
    if(range.front) {
      currentNodeIndex = -codebook[currentNodeIndex];
    } else {
      ++currentNodeIndex;
    }
    currentNode = codebook[currentNodeIndex];
    range.popFront();
  }

  return currentNode;
}

unittest {
  byte[] codebookPlusJunk = [-2, 'b', -4, 'a', -6, 'c', 'd', '*', '*'];
  auto codebook = readMinihuff!byte(new MemoryStream(codebookPlusJunk));
  assert(codebook.length == 7);

  ubyte[] encodedData = [0xED, 0x03]; // Encoded data
  auto dataMemStream = new MemoryStream(encodedData);
  auto range = dataMemStream.byBit();
  string word = "";
  foreach(i; 0..4) {
    word ~= lookupMinihuff(codebook, range);
  }

  assert(word == "acdc");
}
