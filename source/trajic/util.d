module trajic.util;

version(D_InlineAsm_X86_64) {
  private enum InlineAsm = true;
} else version(D_InlineAsm_X86) {
  private enum InlineAsm = true;
} else {
  private enum InlineAsm = false;
}

// Bit scan reverse. Same as taking integer log base 2
int bsr32(int number) {
  static if(InlineAsm) {
    asm {
        bsr EAX, number;
        jnz finish;
        mov EAX, -1;
      finish:
        nop;
    }
  } else {
    foreach_reverse(i; 0..32) {
      if((number >> i) & 1) {
        return i;
      }
    }
    return -1;
  }
}

unittest {
  assert(bsr32(0x0) == -1);
  assert(bsr32(0x5) == 2);
  assert(bsr32(-1) == 31);
  assert(bsr32(0xFFFFFFFF) == 31);
}

int bsr64(long number) {
  version(D_InlineAsm_X86_64) {
    asm {
        bsr RAX, number;
        jnz finish;
        mov RAX, -1;
      finish:
        nop;
    }
  } else {
    if(number & 0xFFFFFFFF00000000) {
      return bsr32(number >> 32) + 32;
    } else {
      return bsr32(cast(int)(number & 0xFFFFFFFF));
    }
  }
}

unittest {
  assert(bsr64(0x0) == -1);
  assert(bsr64(0x0L) == -1);
  assert(bsr64(0x0806000700005000) == 59);
  assert(bsr64(-1) == 63);
  assert(bsr64(0xFFFFFFFFFFFFFFFF) == 63);
}

T lerp(T)(T a, T b, T beta) if(__traits(isFloating, T)) {
  return a + beta * (b - a);
}
