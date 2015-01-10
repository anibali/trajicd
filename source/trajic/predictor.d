module trajic.predictor;

import std.stdio;
import std.exception;

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

  abstract immutable(T) predictNext(const(T[]) past) pure;
}

/**
 * The constant predictor guesses that the next data point will be the
 * same as the previous one.
 */
class ConstantPredictor(T) : Predictor!T {
  override immutable(T) predictNext(const(T[]) past) pure {
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
class LinearPredictor(T) if(__traits(isArithmetic, T)) : Predictor!T {
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
