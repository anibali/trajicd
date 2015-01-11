module trajic.gpsreader;

import trajic.gpspoint;

import std.stream;
import std.range;
import std.string: munch;
import std.conv: parse;
import std.datetime;
import std.exception: enforce;
import std.math;

import std.stdio;

enum GpsFormat {
  Csv,
  Plt,
}

auto createGpsReader(GpsFormat format)(InputStream source) {
  static if(format == GpsFormat.Csv) {
    auto csvReader = CsvInputRange(source);
    csvReader.initialize();
    return csvReader;
  } else static if(format == GpsFormat.Plt) {
    auto pltReader = PltInputRange(source);
    pltReader.initialize();
    return pltReader;
  } else {
    assert(0, "GPS input format not supported");
  }
}

private struct CsvInputRange {
  InputStream source;
  char[] nextLine;
  GpsPoint currentFront;
  bool emptyFlag = false;

  void initialize() {
    while(!source.eof && (nextLine = source.readLine()) == "") {}
    popFront();
  }

  @property bool empty() {
    return emptyFlag;
  }

  void popFront()
  in {
    assert(!empty);
  } body {
    if(!nextLine.empty) {
      munch(nextLine, ", \t");
      currentFront.time = parse!long(nextLine);
      munch(nextLine, ", \t");
      currentFront.latitude = parse!double(nextLine);
      munch(nextLine, ", \t");
      currentFront.longitude = parse!double(nextLine);
      nextLine.length = 0;

      while(!source.eof && (nextLine = source.readLine()).empty) {}
    } else {
      emptyFlag = true;
    }
  }

  @property GpsPoint front()
  in {
    assert(!empty);
  } body {
    return currentFront;
  }
}
static assert(isInputRange!CsvInputRange);
static assert(is(ElementType!CsvInputRange == GpsPoint));

unittest {
  auto csvData = q"EOS
1234, 5.235, 9.324
2123, 6.235, 8.524
3643, 7.235, 7.842
4624, 8.235, 6.529

EOS";
  auto memStream = new MemoryStream(cast(ubyte[])csvData);
  auto csvReader = createGpsReader!(GpsFormat.Csv)(memStream);

  assert(csvReader.front == GpsPoint(1234, 5.235, 9.324));
  csvReader.popFront();
  csvReader.popFront();
  assert(csvReader.front == GpsPoint(3643, 7.235, 7.842));
  assert(csvReader.front == GpsPoint(3643, 7.235, 7.842));
  csvReader.popFront();
  assert(csvReader.front == GpsPoint(4624, 8.235, 6.529));
  assert(csvReader.empty == false);
  csvReader.popFront();
  assert(csvReader.empty == true);
}

private enum MsecsInDay = convert!("days", "msecs")(1);

private struct PltInputRange {
  InputStream source;
  char[] nextLine;
  GpsPoint currentFront;
  bool emptyFlag = false;

  void initialize() {
    foreach(i; 0..6) {
      char[1024] buffer;
      source.readLine(buffer);
    }
    while(!source.eof && (nextLine = source.readLine()) == "") {}
    popFront();
  }

  @property bool empty() {
    return emptyFlag;
  }

  void popFront()
  in {
    assert(!empty);
  } body {
    if(!nextLine.empty) {
      munch(nextLine, ", \t");
      currentFront.latitude = parse!double(nextLine);
      munch(nextLine, ", \t");
      currentFront.longitude = parse!double(nextLine);
      munch(nextLine, ", \t");

      // Skip next two double fields
      parse!double(nextLine);
      munch(nextLine, ", \t");
      parse!double(nextLine);
      munch(nextLine, ", \t");

      double days = parse!double(nextLine);
      munch(nextLine, ", \t");

      currentFront.time = cast(ulong)round(days * MsecsInDay);

      nextLine.length = 0;

      while(!source.eof && (nextLine = source.readLine()).empty) {}
    } else {
      emptyFlag = true;
    }
  }

  @property GpsPoint front()
  in {
    assert(!empty);
  } body {
    return currentFront;
  }
}
static assert(isInputRange!PltInputRange);
static assert(is(ElementType!PltInputRange == GpsPoint));

unittest {
  import std.stdio;

  auto pltData = q"EOS
Geolife trajectory
WGS 84
Altitude is in Feet
Reserved 3
0,2,255,My Track,0,0,2,8421376
0
40.4577,115.9686,0,127.952755905512,39537.3478703704,2008-03-30,08:20:56
40.4570,115.9692,0,127.952755905512,39537.3480208333,2008-03-30,08:21:09
40.4566,115.9695,0,127.952755905512,39537.3480555556,2008-03-30,08:21:12
40.4561,115.9697,0,127.952755905512,39537.3481134259,2008-03-30,08:21:17
EOS";
  auto memStream = new MemoryStream(cast(ubyte[])pltData);
  auto pltReader = createGpsReader!(GpsFormat.Plt)(memStream);
  assert(pltReader.front == GpsPoint(3416026856000, 40.4577, 115.9686));
  pltReader.popFront();
  assert(pltReader.front == GpsPoint(3416026869000, 40.4570, 115.9692));
  pltReader.popFront();
  pltReader.popFront();
  pltReader.popFront();
  assert(pltReader.empty);
}
