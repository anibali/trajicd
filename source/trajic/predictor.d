module trajic.predictor;

import std.math;
import std.range;
import std.conv;

import std.stdio;

/**
 * A common base class for all predictors.
 */
abstract class Predictor(T) {
  void* metadata;

  this(void* metadata) {
    this.metadata = metadata;
  }

  this() {
    this(null);
  }

  abstract immutable(T) predictNext(const(T[]) past);
}

/**
 * The constant predictor guesses that the next data point will be the
 * same as the previous one.
 */
class ConstantPredictor(T) : Predictor!T {
  override immutable(T) predictNext(const(T[]) past) {
    return past[$-1];
  }
}

unittest {
  auto predInt = new ConstantPredictor!int();
  assert(predInt.predictNext([1, 2, 3]) == 3);

  auto predStr = new ConstantPredictor!string();
  assert(predStr.predictNext(["hi", "hello"]) == "hello");
}

/**
 * The linear predictor guesses that the next data point will follow
 * a linear trend from the previous two points.
 */
class LinearPredictor(T) : Predictor!T
  if(__traits(isArithmetic, T))
{
  override immutable(T) predictNext(const(T[]) past) in {
    assert(past.length >= 2);
  } body {
    return cast(T)((past[$-1] * 2) - past[$-2]);
  }
}

unittest {
  auto predInt = new LinearPredictor!int();
  assert(predInt.predictNext([1, 2, 3]) == 4);
  assert(predInt.predictNext([2, 5, 7]) == 9);
}

class PolynomialPredictor(T) : Predictor!T
  if(__traits(isArithmetic, T))
{
  private immutable int maxHistorySize;
  private immutable int polynomialOrder;

  this(int polynomialOrder, int maxHistorySize) {
    this.polynomialOrder = polynomialOrder;
    this.maxHistorySize = maxHistorySize;
  }

  override immutable(T) predictNext(const(T[]) past) in {
    assert(past.length >= 2);
  } body {
    import dstats.regress;

    auto recentPast = past[$-min(past.length, maxHistorySize)..$];

    auto coefficients = polyFitBeta(
      recentPast,
      iota(0, recentPast.length),
      polynomialOrder).to!(real[]);

    return cast(T)poly(recentPast.length, coefficients);
  }
}

unittest {
  auto predInt = new PolynomialPredictor!double(2, 6);
  assert(abs(predInt.predictNext([1, 2, 4, 9, 16, 25]) - 36) < 1);
}
