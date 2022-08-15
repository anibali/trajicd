module trajic.lfd;

import std.stdio;
import std.math: abs, log2;
import std.algorithm;

/*
 * This class finds the optimal way to place dividers amongst an array of
 * bit-length frequencies using a variation of the linear partitioning
 * algorithm.
 *
 * forceMax:    set to true if a divider must correspond to maximum
 *              possible length
 */
class LengthFrequencyDivider(alias forceMax=false)
  if(is(typeof(forceMax) == bool))
{
  private double[] frequencies;
  private int maxDividers;
  private double[][] costs;
  private ulong[][] path;

  /*
   * frequencies: an array containing the distribution of residual bit-lengths
   *              (each element should be between 0 and 1, with all summing to
   *              1)
   * maxDividers: the desired number of dividers
   */
  this(double[] frequencies, int maxDividers)
  in {
    assert(abs(reduce!"a + b"(frequencies) - 1) < 0.001);
  } body {
    this.frequencies = frequencies;
    this.maxDividers = maxDividers;

    costs = new double[][frequencies.length];
    foreach(i; 0..costs.length)
      costs[i] = new double[maxDividers];

    path = new ulong[][frequencies.length];
    foreach(i; 0..path.length)
      path[i] = new ulong[maxDividers];
  }

  void calculate() {
    foreach(i; 0..frequencies.length) {
      costs[i][0] = 0;
      foreach(y; 0..i)
        costs[i][0] += (i - y) * frequencies[y];
    }

    foreach(j; 1..maxDividers)
      costs[0][j] = 0;

    foreach(i; 1..frequencies.length) {
      foreach(j; 1..maxDividers) {
        costs[i][j] = double.infinity;

        foreach(x; (j - 1)..i) {
          double c = costs[x][j - 1];

          foreach(y; (x + 1)..i) {
            c += (i - y) * frequencies[y];
          }

          if(c < costs[i][j]) {
            costs[i][j] = c;
            path[i][j] = x;
          }
        }
      }
    }
  }

  auto getDividers(int nDividers) {
    auto dividerArray = new ulong[nDividers];
    dividerArray[nDividers - 1] = lastDivider(nDividers);
    for(int j = nDividers - 2; j >= 0; --j) {
      dividerArray[j] = path[dividerArray[j + 1]][j + 1];
    }
    return dividerArray;
  }

  double getCost(int nDividers) {
    return costs[lastDivider(nDividers)][nDividers - 1] + log2(nDividers);
  }

  private auto lastDivider(int nDividers) {
    auto x = frequencies.length - 1;
    static if(!forceMax) {
      while(x > nDividers && frequencies[x] == 0) {
        --x;
      }
    }
    return x;
  }
}

unittest {
  double[] frequencies = [
    0.00, 0.50, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.07, 0.00,
    0.03, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.20, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.20, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
    0.00
  ];

  auto lfd = new LengthFrequencyDivider!false(frequencies, 8);
  lfd.calculate();
  assert(lfd.getDividers(4) == [1, 24, 35, 49]);
}
