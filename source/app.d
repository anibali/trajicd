import std.stdio;
import std.range;
import std.stream;
import std.getopt;
import std.path;
import std.file;
import core.time;

import trajic.all;

void main(string[] args) {
  testClusterMemberCompression(args);
}

void doDeltaMemberCompression(string[] inFileNames) {
  import std.algorithm;

  TickDuration compressionTime;
  int rawSize = 0;
  int compressedSize = 0;

  foreach(inFileName; inFileNames) {
    auto inFile = new std.stream.File(inFileName);
    scope(exit) inFile.close();

    long[] numbers;

    while(!inFile.eof) {
      string line = cast(immutable)inFile.readLine();
      auto number = line.parse!long;
      numbers ~= number;
      rawSize += 8;
    }

    // Two initial points are stored raw
    compressedSize += 16;

    if(numbers.length > 2) {
      auto predictor = new trajic.predictor.ConstantPredictor!long();

      auto residuals = new ulong[numbers.length];

      foreach(i; 2..numbers.length) {
        auto prediction = predictor.predictNext(numbers[0..i]);
        auto actual = numbers[i];

        residuals[i] = prediction ^ actual;
        auto residualLength = bsr64(residuals[i]) + 1;

        compressedSize += 6 + residualLength;
      }
    }
  }

  writeln("--- Final stats ---");
  writefln("number_of_trajectories=%d", inFileNames.length);
  writefln("raw_size=%d bytes", rawSize);
  writefln("compressed_size=%d bytes", compressedSize);
  writefln("compression_ratio=%.4f", cast(double)compressedSize / rawSize);
}

void doTrajicMemberCompression(T)(T predictor, string[] inFileNames) {
  import std.algorithm;

  TickDuration compressionTime;
  int rawSize = 0;
  int compressedSize = 0;

  foreach(inFileName; inFileNames) {
    auto inFile = new std.stream.File(inFileName);
    scope(exit) inFile.close();

    long[] numbers;

    while(!inFile.eof) {
      string line = cast(immutable)inFile.readLine();
      auto number = line.parse!long;
      numbers ~= number;
      rawSize += 8;
    }

    // Two initial points are stored raw
    compressedSize += 16;

    if(numbers.length > 2) {
      int[65] residualLengthHistogram;

      auto residuals = new ulong[numbers.length];

      foreach(i; 2..numbers.length) {
        auto prediction = predictor.predictNext(numbers[0..i]);
        auto actual = numbers[i];

        residuals[i] = prediction ^ actual;
        auto residualLength = bsr64(residuals[i]) + 1;
        ++residualLengthHistogram[residualLength];
      }

      double[65] residualLengthFrequencies;

      foreach(residualLength, count; residualLengthHistogram) {
        residualLengthFrequencies[residualLength] = cast(double)count / (residuals.length - 2);
      }

      auto lfd = new LengthFrequencyDivider!false(residualLengthFrequencies, residualLengthFrequencies.length);
      lfd.calculate();
      double[65] costs;
      foreach(int i; 1..costs.length) {
        costs[i] = lfd.getCost(i);
      }
      auto bestNumberOfDividers = cast(int)(costs.length - minPos(costs[1..$]).length);

      auto dividers = lfd.getDividers(bestNumberOfDividers);
      double[byte] frequencyMap;

      int index = 0;
      foreach(divider; dividers) {
        double sum = 0;
        while(index < residualLengthFrequencies.length && index <= divider) {
          sum += residualLengthFrequencies[index++];
        }
        frequencyMap[cast(byte)divider] = sum;
      }

      auto codewordMap = createMinihuff(frequencyMap).assocArray();

      foreach(residual; residuals) {
        auto residualLength = bsr64(residual) + 1;

        ulong bestDivider = -1;
        foreach(divider; dividers) {
          if(residualLength <= divider) {
            bestDivider = divider;
            break;
          }
        }
        compressedSize += bestDivider + codewordMap[cast(byte)bestDivider].length;
      }
    }
  }

  writeln("--- Final stats ---");
  writefln("number_of_trajectories=%d", inFileNames.length);
  writefln("raw_size=%d bytes", rawSize);
  writefln("compressed_size=%d bytes", compressedSize);
  writefln("compression_ratio=%.4f", cast(double)compressedSize / rawSize);
}

void testClusterMemberCompression(string[] args) {
  // dub run -- trajic /home/aiden/Data/Trajectories/IllinoisClustered/Processed/0.1/members/*

  string algorithm = args[1];
  string[] inFileNames = args[2..$];

  if(algorithm == "delta")
    doDeltaMemberCompression(inFileNames);
  else if(algorithm == "trajic")
    doTrajicMemberCompression(new trajic.predictor.LinearPredictor!long, inFileNames);
}

void testTrajectoryCompression(string[] args) {
  string[] inFileNames;

  // TODO: Make use of these values
  double[string] maxError = ["spatial": 0, "temporal": 0];

  // ./trajic --max-error spatial=1,temporal=1 test/car.plt

  arraySep = ",";
  getopt(
    args,
    "max-error", &maxError
  );

  inFileNames = args[1..$];

  TickDuration compressionTime;
  int rawSize = 0;
  int compressedSize = 0;

  foreach(inFileName; inFileNames) {
    auto inFile = new std.stream.File(inFileName);
    scope(exit) inFile.close();

    auto gpsReader = createGpsReader!(GpsFormat.Plt)(inFile);

    auto outFileName = setExtension(inFileName, "tjc");
    auto outFile = new std.stream.File(outFileName, FileMode.OutNew);
    scope(exit) outFile.close();

    TickDuration startTime = TickDuration.currSystemTick();

    auto compressor = createGpsCompressor!(GpsCompression.Predictive)(outFile);
    compressor.compress(gpsReader);

    compressionTime += TickDuration.currSystemTick() - startTime;

    inFile.position = 0;
    gpsReader = createGpsReader!(GpsFormat.Plt)(inFile);
    foreach(_; gpsReader) {
      rawSize += 24; // Raw storage is 24 bytes per point
    }

    compressedSize += getSize(outFileName);
  }

  writeln("--- Final stats ---");
  writefln("number_of_trajectories=%d", inFileNames.length);
  writefln("compression_time=%.3f ms", compressionTime.usecs / 1000.0);
  writefln("mean_compression_time=%.3f ms", compressionTime.usecs / (1000.0 * inFileNames.length));
  writefln("raw_size=%d bytes", rawSize);
  writefln("compressed_size=%d bytes", compressedSize);
  writefln("compression_ratio=%.4f", cast(double)compressedSize / rawSize);
}

// Just playing around
void testSoundCompression() {
  import std.algorithm;
  import derelict.sndfile.sndfile;

  DerelictSndFile.load();

  SF_INFO sndInfo;
  auto sndFile = sf_open("test/sine1000hz.wav", SFM_READ, &sndInfo);
  auto sound = new short[][sndInfo.channels];
  foreach(ref channelData; sound) {
    channelData.length = sndInfo.frames;
  }
  foreach(i; 0..sndInfo.frames) {
    auto frameData = new short[sndInfo.channels];
    sf_readf_short(sndFile, frameData.ptr, 1);
    foreach(channel, amplitude; frameData) {
      sound[channel][i] = amplitude;
    }
  }

  auto predictor = new PolynomialPredictor!short(4, 8);

  foreach(channel; 0..sndInfo.channels) {
    int[17] residualLengthHistogram;

    auto residuals = new ushort[sndInfo.frames];

    // TODO
    //residuals[0] = ...
    //residuals[1] = ...

    foreach(frame; 2..sndInfo.frames) {
      auto prediction = predictor.predictNext(sound[channel][0..frame]);
      auto actual = sound[channel][frame];

      residuals[frame] = prediction ^ actual;
      auto residualLength = bsr64(residuals[frame]) + 1;
      ++residualLengthHistogram[residualLength];
    }

    double[17] residualLengthFrequencies;

    foreach(residualLength, count; residualLengthHistogram) {
      residualLengthFrequencies[residualLength] = cast(double)count / sndInfo.frames;
    }

    auto lfd = new LengthFrequencyDivider!false(residualLengthFrequencies, residualLengthFrequencies.length);
    lfd.calculate();
    double[17] costs;
    foreach(int i; 1..costs.length) {
      costs[i] = lfd.getCost(i);
    }
    auto bestNumberOfDividers = cast(int)(costs.length - minPos(costs[1..$]).length);

    auto dividers = lfd.getDividers(bestNumberOfDividers);
    double[byte] frequencyMap;

    int index = 0;
    foreach(divider; dividers) {
      double sum = 0;
      while(index < residualLengthFrequencies.length && index <= divider) {
        sum += residualLengthFrequencies[index++];
      }
      frequencyMap[cast(byte)divider] = sum;
    }

    auto codewordMap = createMinihuff(frequencyMap).assocArray();

    ulong compressedSize = 0;
    foreach(residual; residuals) {
      auto residualLength = bsr64(residual) + 1;

      ulong bestDivider = -1;
      foreach(divider; dividers) {
        if(residualLength <= divider) {
          bestDivider = divider;
          break;
        }
      }
      compressedSize += bestDivider + codewordMap[cast(byte)bestDivider].length;
    }

    writefln("Approximate channel %d compressed size: %d KiB", channel, compressedSize / (8 * 1024));
  }
}
