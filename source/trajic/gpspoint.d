module trajic.gpspoint;

import std.math;
import std.string: format;

private immutable int EarthRadius = 6371;
private immutable double PiOn180 = PI / 180;

struct GpsPoint {
  static assert(double.sizeof == long.sizeof);

  union {
    struct {
      long time;
      double latitude;
      double longitude;
    }
    struct {
      long[3] data;
    }
  }

  double distance(GpsPoint other) {
    return sqrt(pow(other.latitude - latitude, 2) + pow(other.longitude - longitude, 2));
  }

  /**
   * Calculate the distance between two points in kilometres. Takes the Earth's
   * curvature into consideration using the haversine function.
   */
  double distanceInKilometres(GpsPoint other) const {
    double lat1 = latitude * PiOn180;
    double lat2 = other.latitude * PiOn180;
    double lon1 = longitude * PiOn180;
    double lon2 = other.longitude * PiOn180;

    double dlat = lat2 - lat1;
    double dlon = lon2 - lon1;

    double a = sin(dlat / 2) * sin(dlat / 2) +
               sin(dlon / 2) * sin(dlon / 2) * cos(lat1) * cos(lat2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return EarthRadius * c;
  }

  /**
   * Linear interpolation/extrapolation of a new point at time `atTime` given
   * two points that define a line.
   */
  auto lerp(GpsPoint endPoint, long atTime) {
    double dt = endPoint.time - time;
    double dLat = endPoint.latitude - latitude;
    double dLon = endPoint.longitude - longitude;

    double timeRatio;
    if(dt == 0) {
      timeRatio = 1;
    } else {
      timeRatio = (atTime - time) / dt;
    }

    GpsPoint newPoint = {
      time:       atTime,
      latitude:   latitude + dLat * timeRatio,
      longitude:  longitude + dLon * timeRatio
    };

    return newPoint;
  }

  bool opEquals()(auto ref const GpsPoint other) const {
    bool same = true;
    same = same && time == other.time;
    same = same && abs(latitude - other.latitude) < 0.000001;
    same = same && abs(longitude - other.longitude) < 0.000001;
    return same;
  }

  string toString() {
    return "GpsPoint(t=%d, lat=%.4f, lon=%.4f)".format(time, latitude, longitude);
  }
}

unittest {
  import std.stdio;

  GpsPoint point1 = {23, 51, 85};
  GpsPoint point2 = {24, 54, 89};

  assert(point1.distance(point2) == 5);

  assert(point1.lerp(point2, 25) == GpsPoint(25, 57, 93));
  assert(GpsPoint(12, 12, 12).lerp(GpsPoint(7, 7, 7), 6) == GpsPoint(6, 6, 6));
}
