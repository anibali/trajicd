import std.stdio;
import std.range;
import std.stream;

import trajic.all;

void main() {
  testTrajectoryCompression();
}

void testTrajectoryCompression() {
  auto inFile = new std.stream.File("test/car.plt");
  scope(exit) inFile.close();

  auto gpsReader = createGpsReader!(GpsFormat.Plt)(inFile);

  auto outFile = new std.stream.File("test/tmp.dat", FileMode.OutNew);
  scope(exit) outFile.close();

  auto compressor = createGpsCompressor!(GpsCompression.Predictive)(outFile);
  compressor.compress(gpsReader);
}

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

  auto outstream = new MemoryStream();
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
