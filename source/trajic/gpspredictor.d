module trajic.gpspredictor;

import trajic.gpspoint;
import trajic.util;

import std.stdio;

enum GpsPrediction {
  Constant,
  Linear
}

auto createGpsPredictor(GpsPrediction prediction)() {
  static if(prediction == GpsPrediction.Constant) {
    return ConstantPredictor();
  } else static if(prediction == GpsPrediction.Linear) {
    return LinearPredictor();
  } else {
    assert(0, "GPS prediction algorithm not supported");
  }
}

private struct ConstantPredictor {
  long predictTime(GpsPoint[] pastPoints) {
    return pastPoints[$-1].time;
  }

  GpsPoint predictCoordinates(GpsPoint[] pastPoints, long time) {
    return pastPoints[$-1];
  }
}

private struct LinearPredictor {
  long predictTime(GpsPoint[] pastPoints)
  in {
    assert(pastPoints.length > 1);
  }
  body {
    return pastPoints[$-1].time * 2 - pastPoints[$-2].time;
  }

  GpsPoint predictCoordinates(GpsPoint[] pastPoints, long time)
  in {
    assert(pastPoints.length > 1);
  }
  body {
    return pastPoints[$-2].lerp(pastPoints[$-1], time);
  }
}
