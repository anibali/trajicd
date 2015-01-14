module trajic.gpscompressor;

import trajic.gpspoint;
import trajic.gpspredictor;
import trajic.stream;
import trajic.encoder;
import trajic.util;

import std.stream;
import std.range;
import std.bitmanip;
import std.math;
import std.algorithm;

import std.stdio;

enum GpsCompression {
  Dummy,
  Delta,
  Predictive
}

auto createGpsCompressor(GpsCompression compression)(Stream sink) {
  static if(compression == GpsCompression.Dummy) {
    return DummyCompressor(new BitStream(sink));
  } else static if(compression == GpsCompression.Delta) {
    return DeltaCompressor(new BitStream(sink));
  } else static if(compression == GpsCompression.Predictive) {
    return PredictiveCompressor!(GpsPrediction.Linear)(new BitStream(sink));
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

int bitsToDiscard(double maxValue, double errorBound)
{
  DoubleRep maxVal = {value: maxValue};
  return min(cast(int)log2(errorBound * pow(2.0, 1075 - maxVal.exponent) + 1), 52);
}

unittest {
  int maxValue = 50;
  double maxError = 0.5;

  auto discard = bitsToDiscard(maxValue, maxError);

  union Bits64 {
    double doubleVal;
    long longVal;
  }

  double step = 0.1;

  foreach(i; 0..(maxValue / step)) {
    auto x = i * step;

    Bits64 fortyTwo = {doubleVal:x};
    fortyTwo.longVal >>= discard;
    fortyTwo.longVal <<= discard;
    assert(abs(fortyTwo.doubleVal - x) < maxError);
  }
}

private struct PredictiveCompressor(GpsPrediction prediction) {
  BitStream sink;
  long maxTemporalError = 0;
  double maxSpatialError = 0;

  void compress(R)(R range) if(isInputRange!R && is(ElementType!R == GpsPoint))
  {
    auto predictor = createGpsPredictor!(prediction)();

    long maxTime = 0;
    double maxCoordinate = 0;

    auto points = array(range);

    foreach(point; points)
    {
      maxTime = max(maxTime, abs(point.time));
      maxCoordinate = max(maxCoordinate, abs(point.latitude), abs(point.longitude));
    }
    
    int[3] discard;
    discard[0] = bsr64(maxTemporalError);
    if(discard[0] < 0) discard[0] = 0;
    discard[1] = bitsToDiscard(maxCoordinate, maxTemporalError);
    discard[2] = discard[1];
    
    sink.writeBits(discard[0], 8);
    sink.writeBits(discard[1], 8);
    
    sink.writeBits(points.length, 32);

    immutable int nStartingPoints = 2;
    
    foreach(i; 0..nStartingPoints) {
      foreach(field; points[0].data) {
        sink.writeBits(field, 64);
      }
    }

    immutable auto nResiduals = points.length - nStartingPoints;
    
    ulong[][3] residuals;
    foreach(ref residualChannel; residuals) {
      residualChannel.length = nResiduals;
    }

    foreach(i; nStartingPoints..points.length) {
      long time = points[i].time;

      if(discard[0] > 0) {
        long predictedTime = predictor.predictTime(points[0..i]);
        ulong residual = points[i].time ^ predictedTime;
        residual = (residual >> discard[0]) << discard[0];
        time = predictedTime ^ residual;
      }

      GpsPoint predictedPoint = predictor.predictCoordinates(points[0..i], time);
      
      foreach(j; 0..3) {
        ulong residual = points[i].data[j] ^ predictedPoint.data[j];
        residual >>= discard[j];
        residuals[j][i - nStartingPoints] = residual;
        residual <<= discard[j];
        points[i].data[j] = predictedPoint.data[j] ^ residual;
      }
    }

    // TODO: Implement encoders
    
    auto encoders = [
      createEncoder!(Encoding.Dynamic)(sink, residuals[0]),
      createEncoder!(Encoding.Dynamic)(sink, residuals[1]),
      createEncoder!(Encoding.Dynamic)(sink, residuals[2])
    ];

    foreach(i; 0..nResiduals) {
      foreach(j; 0..3) {
        encoders[j].encode(residuals[j][i]);
      }
    }
  }
}

unittest {
  auto sink = new BitStream(new MemoryStream());
  scope(exit) sink.close();

  PredictiveCompressor!(GpsPrediction.Linear) compressor = {sink};
  GpsPoint[] points = [
    GpsPoint(1234, 5.235, 9.324),
    GpsPoint(2123, 6.235, 8.524),
    GpsPoint(3643, 7.235, 7.842),
    GpsPoint(4624, 8.235, 6.529)
  ];
  compressor.compress(points);

  // TODO: Test PredictiveCompressor
}
