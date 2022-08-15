module trajic.stream;

import std.stream;
import std.range;
import std.stdio;

private struct InputBitRange {
  // Source of data
  InputStream source;
  // Single-byte buffer
  private ubyte buf;
  // Current position within buffer byte (0-7 in bounds, 8+ out of bounds)
  private size_t pos = 8;
  // Current bit (true = 1, false = 0)
  private bool curFront;

  /**
   * Returns true if and only if there are no more bits to be read
   */
  @property bool empty() {
    return pos > 7 && source.eof;
  }

  /**
   * Moves to the next bit in the range
   */
  void popFront()
  in {
    assert(!empty);
  } body {
    // Ensures read head moves when popFront() is called multiple times in a row
    front();
    // Update current front. If position is pushed out of bounds it will be
    // handled inside the front() call to maximise laziness
    curFront = ((buf >> ++pos) & 1) == 1;
  }

  /**
   * Returns the current bit in the range
   */
  @property bool front()
  in {
    assert(!empty);
  } body {
    // Check whether position is out of bounds
    if(pos > 7) {
      // Read next byte into buffer
      source.read(buf);
      // Reset position in buffer byte
      pos = 0;
      // Set proper value for curFront
      curFront = (buf & 1) == 1;
    }
    // Return current front bit
    return curFront;
  }
}
static assert(isInputRange!InputBitRange);
static assert(is(ElementType!InputBitRange == bool));

/**
 * Returns a range for reading the source stream one bit at a time
 */
auto byBit(InputStream source) {
  return InputBitRange(source);
}
static assert(isInputRange!(std.traits.ReturnType!byBit));

unittest {
  ubyte[] data = [3, 42, 255, 0, 255];

  // Create representation of data as a binary string
  // (expected bits to be read in)
  string expected;
  char[8] buf;
  foreach(byt; data) {
    std.string.sformat(buf, "%08b", byt);
    buf.reverse;
    expected ~= buf;
  }

  // Create InputBitRange
  auto memStream = new MemoryStream(data);
  auto r = memStream.byBit();

  // Assert that InputBitRange results match expectations
  foreach(chr; expected) {
    assert((chr == '1') == r.front);
    r.popFront();
  }
  assert(r.empty, "Range should be empty");
}

unittest {
  ubyte[] data = [1, 0, 128];

  // Create InputBitRange
  auto memStream = new MemoryStream(data);
  auto r = memStream.byBit();

  assert(r.front == true); r.popFront();
  assert(r.front == false); r.popFront();
  for(int i = 0; i < 12 + (data.length - 2) * 8; ++i) {
    r.popFront();
  }
  assert(r.front == false); r.popFront();
  assert(r.front == true); r.popFront();

  assert(r.empty, "Range should be empty");
}

class BitStream : FilterStream {
  ubyte part = 0;
  size_t pos = 0;

  this(Stream sink) {
    super(sink);
  }

  void writeBits(ulong val, size_t nBits) {
    part |= (val << pos) & 0xFF;
    val >>= 8 - pos;

    if(nBits + pos >= 8) {
      super.write(part);

      nBits -= 8 - pos;

      for(int i = 0; i < nBits / 8; ++i) {
        super.write(cast(ubyte)(val & 0xFF));
        val >>= 8;
      }

      pos = nBits % 8;
      part = val & (0xFF >> 8 - pos);
    } else {
      pos += nBits;
    }
  }

  void writeBit(bool val) {
    writeBits(val ? 1 : 0, 1);
  }

  bool readBit() {
    if(pos > 7) {
      read(part);
      pos = 0;
    }
    return ((part >> pos++) & 1) == 1;
  }

  override void flush() {
    if(pos > 0) {
      super.write(part);
      seekCur(-1);
    }
    super.flush();
  }
}

unittest {
  BitStream stream = new BitStream(new MemoryStream());
  // ASCII for 't' is 01110100b (0x74)
  stream.writeBits(0, 2);
  stream.writeBit(true);
  stream.writeBit(false);
  stream.writeBits(7, 3);
  stream.flush();
  stream.seekSet(0);
  assert(stream.getc() == 't');
  stream.close();
}
