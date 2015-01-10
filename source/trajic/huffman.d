module trajic.huffman;

import trajic.stream;

import std.algorithm;
import std.container;
import std.typecons;
import std.range;
import std.string;
import std.conv: to;
import std.math;
import std.stream;

string[T] createHuffman(alias canonical=true, T)(double[T] frequencyMap) {
  alias Pair = Tuple!(T, "symbol", string, "code");
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
  static if(canonical) {
    canonicalize(codewords);
  }
  return codewords.assocArray();
}

private void canonicalize(R)(R codewords) if(isRandomAccessRange!R && 
  isTuple!(ElementType!R) && ElementType!R.length == 2)
{
  codewords.multiSort!("a.code.length < b.code.length", "a.symbol < b.symbol",
    SwapStrategy.unstable);
  int codeword = -1;
  ulong prevLen = 1;
  for(int i = 0; i < codewords.length; ++i) {
    ++codeword;
    codeword <<= codewords[i].code.length - prevLen;
    prevLen = codewords[i].code.length;
    codewords[i].code = format("%0"~to!string(prevLen)~"b", codeword);
  }
}

struct HuffmanNode(T) {
  private union {
    struct {
      HuffmanNode!T* _zero;
      HuffmanNode!T* _one;
    }
    T _symbol;
  }
  bool leaf;

  @property ref auto symbol()
  in {
    assert(leaf, "Node is not a leaf node");
  } body {
    return _symbol;
  }

  @property ref auto zero()
  in {
    assert(!leaf, "Node is not a branch node");
  } body {
    return _zero;
  }

  @property ref auto one()
  in {
    assert(!leaf, "Node is not a branch node");
  } body {
    return _one;
  }

  T lookup(R)(ref R range) if(isInputRange!R && is(ElementType!R == bool)) {
    HuffmanNode!T* currentNode = &this;

    while(!currentNode.leaf) {
      if(range.front) {
        currentNode = currentNode.one;
      } else {
        currentNode = currentNode.zero;
      }
      range.popFront();
    }

    return currentNode.symbol;
  }
}

auto readHuffman(T)(T[] alphabet, InputStream instream) {
  alias Pair = Tuple!(T, "symbol", string, "code");

  auto range = instream.byBit();

  size_t nCodewords = alphabet.length;

  // Read byte
  ubyte nBits = 0;
  for(int i = 0; i < 8; ++i) {
    if(range.front())
      nBits |= (1 << i);
    range.popFront();
  }

  char[] binary;
  Pair[] pairs;
  foreach(symbol; alphabet) {
    // Read int
    size_t len = 0;
    foreach(i; 0..nBits) {
      if(range.front())
        len |= (1 << i);
      range.popFront();
    }
    binary.length = len;
    pairs ~= Pair(symbol, cast(string)binary);
  }

  canonicalize(pairs);

  // Make sure all nodes are in contiguous memory for CPU caching
  auto nodePool = new HuffmanNode!T[pairs.length * 2 - 1];
  auto nodePoolIndex = 0;

  auto rootNode = &nodePool[nodePoolIndex++];

  foreach(pair; pairs) {
    auto currentNode = rootNode;

    // Traverse/create path through tree
    foreach(bit; pair.code[0..$]) {
      if(bit == '1') {
        if(currentNode.one is null) {
          currentNode.one = &nodePool[nodePoolIndex++];
        }
        currentNode = currentNode.one;
      } else {
        if(currentNode.zero is null) {
          currentNode.zero = &nodePool[nodePoolIndex++];
        }
        currentNode = currentNode.zero;
      }
    }

    // Set symbol in leaf node
    currentNode.leaf = true;
    currentNode.symbol = pair.symbol;
  }

  return rootNode;
}

unittest {
  ubyte[] encodedCodebook = [0x02, 0xF6]; // Encoded codebook
  auto memStream = new MemoryStream(encodedCodebook);
  auto huffmanTree = readHuffman(["a", "b", "c", "d"], memStream);
  assert(huffmanTree.one.zero.symbol == "a");
  assert(huffmanTree.zero.symbol == "b");
  assert(huffmanTree.one.one.zero.symbol == "c");
  assert(huffmanTree.one.one.one.symbol == "d");

  ubyte[] encodedData = [0xED, 0x03]; // Encoded data
  auto dataMemStream = new MemoryStream(encodedData);
  auto range = dataMemStream.byBit();
  string word = "";
  foreach(i; 0..4) {
    word ~= huffmanTree.lookup(range);
  }
  assert(word == "acdc");
}

void writeHuffman(T)(string[T] codebook, BitStream outstream) {
  const ulong maxLen = codebook.values.map!"a.length".reduce!"a > b ? a : b";
  const int nBits = cast(int)log2(maxLen) + 1;
  outstream.writeBits(nBits, 8);

  alias Pair = Tuple!(T, "symbol", ulong, "codeLength");
  Pair[] r;
  foreach(symbol, code; codebook)
    r ~= Pair(symbol, code.length);
  sort!"a.symbol < b.symbol"(r);
  foreach(pair; r)
    outstream.writeBits(pair.codeLength, nBits);
}

unittest {
  auto freqMap = ["a": 0.3, "b": 0.5, "c": 0.1, "d": 0.1];

  auto codebook = createHuffman!false(freqMap);
  assert(codebook["a"].length == 2);
  assert(codebook["b"].length == 1);
  assert(codebook["c"].length == 3);
  assert(codebook["d"].length == 3);

  auto canonicalCodebook = createHuffman!true(freqMap);
  assert(canonicalCodebook["a"] == "10");
  assert(canonicalCodebook["b"] == "0");
  assert(canonicalCodebook["c"] == "110");
  assert(canonicalCodebook["d"] == "111");
}
