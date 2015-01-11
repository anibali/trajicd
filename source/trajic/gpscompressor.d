module trajic.gpscompressor;

import trajic.gpspoint;
import trajic.stream;
import trajic.util;

import std.stream;
import std.range;

import std.stdio;

enum GpsCompression {
  Dummy,
  Delta
}

auto createGpsCompressor(GpsCompression compression)(Stream sink) {
  static if(compression == GpsCompression.Dummy) {
    return DummyCompressor(new BitStream(sink));
  } else static if(compression == GpsCompression.Delta) {
    return DeltaCompressor(new BitStream(sink));
  } else {
    assert(0, "GPS compression algorithm not supported");
  }
}

/**
 * Simply stores points using full-size binary data types
 */
private struct DummyCompressor {
  BitStream sink;

  void compress(R)(R points) if(isInputRange!R && is(ElementType!R == GpsPoint))
  {
    foreach(point; points) {
      foreach(field; point.data) {
        sink.write(field);
      }
    }

    sink.nestClose = false;
    sink.close();
  }
}

/**
 * Stores points as deltas from the previous point, with deltas encoded as
 * a delta length, n, (6 bits) followed by the delta value (n bits)
 */
private struct DeltaCompressor {
  BitStream sink;

  void compress(R)(R points) if(isInputRange!R && is(ElementType!R == GpsPoint))
  {
    GpsPoint prevPoint = points.front;
    points.popFront();

    foreach(field; prevPoint.data) {
      sink.write(field);
    }

    foreach(point; points) {
      foreach(j; 0..3) {
        long delta = point.data[j] ^ prevPoint.data[j];
        
        int deltaBits = 0;
        if(delta > 0) deltaBits = bsr64(delta);

        sink.writeBits(deltaBits, 6);
        sink.writeBits(delta, deltaBits + 1);
      }

      prevPoint = point;
    }

    sink.nestClose = false;
    sink.close();
  }
}
