//===-- SPIRVBitOps.td - MLIR SPIR-V Bit Ops -*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file contains bit ops for the SPIR-V dialect. It corresponds
// to "3.32.13. Bit Instructions" of the SPIR-V specification.
//
//===----------------------------------------------------------------------===//

#ifndef MLIR_DIALECT_SPIRV_IR_BIT_OPS
#define MLIR_DIALECT_SPIRV_IR_BIT_OPS

include "mlir/Dialect/SPIRV/IR/SPIRVBase.td"
include "mlir/Interfaces/SideEffectInterfaces.td"

class SPIRV_BitBinaryOp<string mnemonic, list<Trait> traits = []> :
      // All the operands type used in bit instructions are SPIRV_Integer.
      SPIRV_BinaryOp<mnemonic, SPIRV_Integer, SPIRV_Integer,
                   !listconcat(traits,
                               [NoSideEffect, SameOperandsAndResultType])> {
  let assemblyFormat = "operands attr-dict `:` type($result)";
}

class SPIRV_BitFieldExtractOp<string mnemonic, list<Trait> traits = []> :
      SPIRV_Op<mnemonic, !listconcat(traits,
             [NoSideEffect, AllTypesMatch<["base", "result"]>])> {
  let arguments = (ins
    SPIRV_ScalarOrVectorOf<SPIRV_Integer>:$base,
    SPIRV_Integer:$offset,
    SPIRV_Integer:$count
  );

  let results = (outs
    SPIRV_ScalarOrVectorOf<SPIRV_Integer>:$result
  );

  let hasVerifier = 0;

  let assemblyFormat = [{
    operands attr-dict `:` type($base) `,` type($offset) `,` type($count)
  }];
}

class SPIRV_BitUnaryOp<string mnemonic, list<Trait> traits = []> :
      SPIRV_UnaryOp<mnemonic, SPIRV_Integer, SPIRV_Integer,
                   !listconcat(traits,
                               [NoSideEffect, SameOperandsAndResultType])>;

class SPIRV_ShiftOp<string mnemonic, list<Trait> traits = []> :
      SPIRV_BinaryOp<mnemonic, SPIRV_Integer, SPIRV_Integer,
                   !listconcat(traits,
                               [NoSideEffect, SameOperandsAndResultShape,
                                AllTypesMatch<["operand1", "result"]>])> {
  let assemblyFormat = [{
    operands attr-dict `:` type($operand1) `,` type($operand2)
  }];
  let hasVerifier = 1;
}

// -----

def SPIRV_BitCountOp : SPIRV_BitUnaryOp<"BitCount", []> {
  let summary = "Count the number of set bits in an object.";

  let description = [{
     Results are computed per component.

    Result Type must be a scalar or vector of integer type.  The components
    must be wide enough to hold the unsigned Width of Base as an unsigned
    value. That is, no sign bit is needed or counted when checking for a
    wide enough result width.

    Base must be a scalar or vector of integer type.  It must have the same
    number of components as Result Type.

    The result is the unsigned value that is the number of bits in Base that
    are 1.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitcount-op ::= ssa-id `=` `spirv.BitCount` ssa-use
                               `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.BitCount %0: i32
    %3 = spirv.BitCount %1: vector<4xi32>
    ```
  }];
}

// -----

def SPIRV_BitFieldInsertOp : SPIRV_Op<"BitFieldInsert",
    [NoSideEffect, AllTypesMatch<["base", "insert", "result"]>]> {
  let summary = [{
    Make a copy of an object, with a modified bit field that comes from
    another object.
  }];

  let description = [{
     Results are computed per component.

    Result Type must be a scalar or vector of integer type.

     The type of Base and Insert must be the same as Result Type.

    Any result bits numbered outside [Offset, Offset + Count -  1]
    (inclusive) will come from the corresponding bits in Base.

    Any result bits numbered in [Offset, Offset + Count -  1] come, in
    order, from the bits numbered [0, Count - 1] of Insert.

    Count  must be an integer type scalar. Count is the number of bits taken
    from Insert. It will be consumed as an unsigned value. Count can be 0,
    in which case the result will be Base.

    Offset  must be an integer type scalar. Offset is the lowest-order bit
    of the bit field.  It will be consumed as an unsigned value.

    The resulting value is undefined if Count or Offset or their sum is
    greater than the number of bits in the result.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitfield-insert-op ::= ssa-id `=` `spirv.BitFieldInsert` ssa-use `,` ssa-use
                                      `,` ssa-use `,` ssa-use
                                      `:` integer-scalar-vector-type
                                      `,` integer-type `,` integer-type
    ```

    #### Example:

    ```mlir
    %0 = spirv.BitFieldInsert %base, %insert, %offset, %count : vector<3xi32>, i8, i8
    ```
  }];

  let availability = [
    MinVersion<SPIRV_V_1_0>,
    MaxVersion<SPIRV_V_1_6>,
    Extension<[]>,
    Capability<[SPIRV_C_BitInstructions, SPIRV_C_Shader]>
  ];

  let arguments = (ins
    SPIRV_ScalarOrVectorOf<SPIRV_Integer>:$base,
    SPIRV_ScalarOrVectorOf<SPIRV_Integer>:$insert,
    SPIRV_Integer:$offset,
    SPIRV_Integer:$count
  );

  let results = (outs
    SPIRV_ScalarOrVectorOf<SPIRV_Integer>:$result
  );

  let hasVerifier = 0;

  let assemblyFormat = [{
    operands attr-dict `:` type($base) `,` type($offset) `,` type($count)
  }];
}

// -----

def SPIRV_BitFieldSExtractOp : SPIRV_BitFieldExtractOp<"BitFieldSExtract",
                                                   [SignedOp]> {
  let summary = "Extract a bit field from an object, with sign extension.";

  let description = [{
     Results are computed per component.

    Result Type must be a scalar or vector of integer type.

     The type of Base must be the same as Result Type.

    If Count is greater than 0: The bits of Base numbered in [Offset, Offset
    + Count -  1] (inclusive) become the bits numbered [0, Count - 1] of the
    result. The remaining bits of the result will all be the same as bit
    Offset + Count -  1 of Base.

    Count  must be an integer type scalar. Count is the number of bits
    extracted from Base. It will be consumed as an unsigned value. Count can
    be 0, in which case the result will be 0.

    Offset  must be an integer type scalar. Offset is the lowest-order bit
    of the bit field to extract from Base.  It will be consumed as an
    unsigned value.

    The resulting value is undefined if Count or Offset or their sum is
    greater than the number of bits in the result.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitfield-extract-s-op ::= ssa-id `=` `spirv.BitFieldSExtract` ssa-use
                                         `,` ssa-use `,` ssa-use
                                         `:` integer-scalar-vector-type
                                         `,` integer-type `,` integer-type
    ```

    #### Example:

    ```mlir
    %0 = spirv.BitFieldSExtract %base, %offset, %count : vector<3xi32>, i8, i8
    ```
  }];

  let availability = [
    MinVersion<SPIRV_V_1_0>,
    MaxVersion<SPIRV_V_1_6>,
    Extension<[]>,
    Capability<[SPIRV_C_BitInstructions, SPIRV_C_Shader]>
  ];
}

// -----

def SPIRV_BitFieldUExtractOp : SPIRV_BitFieldExtractOp<"BitFieldUExtract",
                                                   [UnsignedOp]> {
  let summary = "Extract a bit field from an object, without sign extension.";

  let description = [{
    The semantics are the same as with OpBitFieldSExtract with the exception
    that there is no sign extension. The remaining bits of the result will
    all be 0.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitfield-extract-u-op ::= ssa-id `=` `spirv.BitFieldUExtract` ssa-use
                                         `,` ssa-use `,` ssa-use
                                         `:` integer-scalar-vector-type
                                         `,` integer-type `,` integer-type
    ```

    #### Example:

    ```mlir
    %0 = spirv.BitFieldUExtract %base, %offset, %count : vector<3xi32>, i8, i8
    ```
  }];

  let availability = [
    MinVersion<SPIRV_V_1_0>,
    MaxVersion<SPIRV_V_1_6>,
    Extension<[]>,
    Capability<[SPIRV_C_BitInstructions, SPIRV_C_Shader]>
  ];
}

// -----

def SPIRV_BitReverseOp : SPIRV_BitUnaryOp<"BitReverse", []> {
  let summary = "Reverse the bits in an object.";

  let description = [{
     Results are computed per component.

    Result Type must be a scalar or vector of integer type.

     The type of Base must be the same as Result Type.

    The bit-number n of the result will be taken from bit-number Width - 1 -
    n of Base, where Width is the OpTypeInt operand of the Result Type.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                   `vector<` integer-literal `x` integer-type `>`
    bitreverse-op ::= ssa-id `=` `spirv.BitReverse` ssa-use
                                 `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.BitReverse %0 : i32
    %3 = spirv.BitReverse %1 : vector<4xi32>
    ```
  }];

  let availability = [
    MinVersion<SPIRV_V_1_0>,
    MaxVersion<SPIRV_V_1_6>,
    Extension<[]>,
    Capability<[SPIRV_C_BitInstructions, SPIRV_C_Shader]>
  ];
}

// -----

def SPIRV_BitwiseAndOp : SPIRV_BitBinaryOp<"BitwiseAnd",
                                       [Commutative, UsableInSpecConstantOp]> {
  let summary = [{
    Result is 1 if both Operand 1 and Operand 2 are 1. Result is 0 if either
    Operand 1 or Operand 2 are 0.
  }];

  let description = [{
     Results are computed per component, and within each component, per bit.

    Result Type must be a scalar or vector of integer type.  The type of
    Operand 1 and Operand 2  must be a scalar or vector of integer type.
    They must have the same number of components as Result Type. They must
    have the same component width as Result Type.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitwise-and-op ::= ssa-id `=` `spirv.BitwiseAnd` ssa-use, ssa-use
                                  `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.BitwiseAnd %0, %1 : i32
    %2 = spirv.BitwiseAnd %0, %1 : vector<4xi32>
    ```
  }];
}

// -----

def SPIRV_BitwiseOrOp : SPIRV_BitBinaryOp<"BitwiseOr",
                                      [Commutative, UsableInSpecConstantOp]> {
  let summary = [{
    Result is 1 if either Operand 1 or Operand 2 is 1. Result is 0 if both
    Operand 1 and Operand 2 are 0.
  }];

  let description = [{
     Results are computed per component, and within each component, per bit.

    Result Type must be a scalar or vector of integer type.  The type of
    Operand 1 and Operand 2  must be a scalar or vector of integer type.
    They must have the same number of components as Result Type. They must
    have the same component width as Result Type.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitwise-or-op ::= ssa-id `=` `spirv.BitwiseOr` ssa-use, ssa-use
                                  `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.BitwiseOr %0, %1 : i32
    %2 = spirv.BitwiseOr %0, %1 : vector<4xi32>
    ```
  }];
}

// -----

def SPIRV_BitwiseXorOp : SPIRV_BitBinaryOp<"BitwiseXor",
                                       [Commutative, UsableInSpecConstantOp]> {
  let summary = [{
    Result is 1 if exactly one of Operand 1 or Operand 2 is 1. Result is 0
    if Operand 1 and Operand 2 have the same value.
  }];

  let description = [{
     Results are computed per component, and within each component, per bit.

    Result Type must be a scalar or vector of integer type.  The type of
    Operand 1 and Operand 2  must be a scalar or vector of integer type.
    They must have the same number of components as Result Type. They must
    have the same component width as Result Type.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    bitwise-xor-op ::= ssa-id `=` `spirv.BitwiseXor` ssa-use, ssa-use
                                  `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.BitwiseXor %0, %1 : i32
    %2 = spirv.BitwiseXor %0, %1 : vector<4xi32>
    ```
  }];
}

// -----

def SPIRV_ShiftLeftLogicalOp : SPIRV_ShiftOp<"ShiftLeftLogical",
                                         [UsableInSpecConstantOp]> {
  let summary = [{
    Shift the bits in Base left by the number of bits specified in Shift.
    The least-significant bits are zero filled.
  }];

  let description = [{
    Result Type must be a scalar or vector of integer type.

     The type of each Base and Shift must be a scalar or vector of integer
    type. Base and Shift must have the same number of components.  The
    number of components and bit width of the type of Base must be the same
    as in Result Type.

    Shift is treated as unsigned. The result is undefined if Shift is
    greater than or equal to the bit width of the components of Base.

    The number of components and bit width of Result Type must match those
    Base type. All types must be integer types.

     Results are computed per component.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    shift-left-logical-op ::= ssa-id `=` `spirv.ShiftLeftLogical`
                                          ssa-use `,` ssa-use `:`
                                          integer-scalar-vector-type `,`
                                          integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.ShiftLeftLogical %0, %1 : i32, i16
    %5 = spirv.ShiftLeftLogical %3, %4 : vector<3xi32>, vector<3xi16>
    ```
  }];
}

// -----

def SPIRV_ShiftRightArithmeticOp : SPIRV_ShiftOp<"ShiftRightArithmetic",
                                             [UsableInSpecConstantOp]> {
  let summary = [{
    Shift the bits in Base right by the number of bits specified in Shift.
    The most-significant bits are filled with the sign bit from Base.
  }];

  let description = [{
    Result Type must be a scalar or vector of integer type.

     The type of each Base and Shift must be a scalar or vector of integer
    type. Base and Shift must have the same number of components.  The
    number of components and bit width of the type of Base must be the same
    as in Result Type.

    Shift is treated as unsigned. The result is undefined if Shift is
    greater than or equal to the bit width of the components of Base.

     Results are computed per component.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    shift-right-arithmetic-op ::= ssa-id `=` `spirv.ShiftRightArithmetic`
                                              ssa-use `,` ssa-use `:`
                                              integer-scalar-vector-type `,`
                                              integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.ShiftRightArithmetic %0, %1 : i32, i16
    %5 = spirv.ShiftRightArithmetic %3, %4 : vector<3xi32>, vector<3xi16>
    ```
  }];
}

// -----

def SPIRV_ShiftRightLogicalOp : SPIRV_ShiftOp<"ShiftRightLogical",
                                          [UsableInSpecConstantOp]> {
  let summary = [{
    Shift the bits in Base right by the number of bits specified in Shift.
    The most-significant bits are zero filled.
  }];

  let description = [{
    Result Type must be a scalar or vector of integer type.

     The type of each Base and Shift must be a scalar or vector of integer
    type. Base and Shift must have the same number of components.  The
    number of components and bit width of the type of Base must be the same
    as in Result Type.

    Shift is consumed as an unsigned integer. The result is undefined if
    Shift is greater than or equal to the bit width of the components of
    Base.

     Results are computed per component.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    shift-right-logical-op ::= ssa-id `=` `spirv.ShiftRightLogical`
                                           ssa-use `,` ssa-use `:`
                                           integer-scalar-vector-type `,`
                                           integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.ShiftRightLogical %0, %1 : i32, i16
    %5 = spirv.ShiftRightLogical %3, %4 : vector<3xi32>, vector<3xi16>
    ```
  }];
}

// -----

def SPIRV_NotOp : SPIRV_BitUnaryOp<"Not", [UsableInSpecConstantOp]> {
  let summary = "Complement the bits of Operand.";

  let description = [{
     Results are computed per component, and within each component, per bit.

    Result Type must be a scalar or vector of integer type.

    Operand's type  must be a scalar or vector of integer type.  It must
    have the same number of components as Result Type.  The component width
    must equal the component width in Result Type.

    <!-- End of AutoGen section -->

    ```
    integer-scalar-vector-type ::= integer-type |
                                  `vector<` integer-literal `x` integer-type `>`
    not-op ::= ssa-id `=` `spirv.BitNot` ssa-use `:` integer-scalar-vector-type
    ```

    #### Example:

    ```mlir
    %2 = spirv.Not %0 : i32
    %3 = spirv.Not %1 : vector<4xi32>
    ```
  }];
}

#endif // MLIR_DIALECT_SPIRV_IR_BIT_OPS
