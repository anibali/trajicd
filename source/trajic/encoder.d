module trajic.encoder;

import trajic.stream;
import trajic.minihuff;
import trajic.lfd;
import trajic.util;

import std.algorithm;
import std.array;

import std.stdio;

enum Encoding {
  Dynamic,
}

auto createEncoder(Encoding encoding, T)(BitStream sink, T[] samples) {
  static if(encoding == Encoding.Dynamic) {
    auto dynamicEncoder = DynamicEncoder!T(sink);
    dynamicEncoder.initialize(samples);
    return dynamicEncoder;
  } else {
    assert(0, "GPS prediction algorithm not supported");
  }
}

struct DynamicEncoder(T) {
  BitStream sink;
  private string[byte] codewordMap;
  
  void initialize(T[] samples) {
    enum nPossibleLengths = T.sizeof * 8 + 1;

    int[nPossibleLengths] lengthHistogram;

    foreach(sample; samples) {
      auto length = bsr64(sample) + 1;
      ++lengthHistogram[length];
    }

    double[nPossibleLengths] lengthFrequencies;

    foreach(length, count; lengthHistogram) {
      lengthFrequencies[length] = cast(double)count / samples.length;
    }

    enum maxDividers = nPossibleLengths;

    auto lfd = new LengthFrequencyDivider!false(lengthFrequencies, maxDividers);
    lfd.calculate();
    double[maxDividers] costs;
    foreach(int i; 1..maxDividers) {
      costs[i] = lfd.getCost(i);
    }
    auto bestNumberOfDividers = cast(int)(costs.length - minPos(costs[1..$]).length);

    auto dividers = lfd.getDividers(bestNumberOfDividers);
    double[byte] frequencyMap;

    int index = 0;
    foreach(divider; dividers) {
      double sum = 0;
      while(index < lengthFrequencies.length && index <= divider) {
        sum += lengthFrequencies[index];
        ++index;
      }
      frequencyMap[cast(byte)divider] = sum;
    }

    auto minihuff = createMinihuff(frequencyMap);

    codewordMap = minihuff.assocArray();

    foreach(node; encodeMinihuff(minihuff)) {
      sink.writeBits(node, 8);
    }
  }

  void encode(T item) {
    auto length = cast(byte)bsr64(item) + 1;

    auto bestDivider = byte.max;

    // TODO: pre-sort dividers to make this faster?
    foreach(divider; codewordMap.keys) {
      if(length <= divider && divider < bestDivider) {
        bestDivider = divider;
      }
    }

    foreach(character; codewordMap[bestDivider]) {
      sink.writeBit(character == '1');
    }

    sink.writeBits(item, bestDivider);
  }
}

unittest {
  import std.stream;

  auto memStream = new MemoryStream();
  auto sink = new BitStream(memStream);
  scope(exit) sink.close();

  DynamicEncoder!uint dynamicEncoder = {sink};

  dynamicEncoder.initialize([2, 3, 5, 3, 7, 6, 45, 52, 47, 43, 234]);
  auto codewordMap = dynamicEncoder.codewordMap;
  assert(codewordMap == cast(typeof(codewordMap))[8:"11", 6:"10", 3:"0"]);

  dynamicEncoder.encode(0); // Should write 000_0b (= 0x0)
  dynamicEncoder.encode(1); // Should write 001_0b (= 0x2)
  dynamicEncoder.encode(15); // Should write 001111_01b (= 0x3D)

  sink.flush();

  assert(memStream.data == [254, 3, 252, 6, 8, 0x20, 0x3D]);
}
