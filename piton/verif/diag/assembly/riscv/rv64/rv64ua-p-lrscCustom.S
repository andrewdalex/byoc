# See LICENSE for license details.

#*****************************************************************************
# lrsr.S
#-----------------------------------------------------------------------------
#
# Test LR/SC instructions.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV64U
RVTEST_CODE_BEGIN


TEST_CASE( 1, a1, 1, \
  la a0, foo; \
  lr.w a1, (a0); \
)

TEST_CASE( 2, a4, 0, \
  la a0, foo; \
  li a5, 0xdeadbeef; \
  lr.w a1, (a0); \
  sc.w a4, a5, (a0); \
)
# 
TEST_CASE( 3, a4, 1, \
  la a0, foo; \
  li a5, 0xdeadbeef; \
  sc.w a4, a5, (a0); \
)


TEST_CASE( 4, a4, 1, \
  la a0, foo; \
  la a1, fooTest3; \
  lr.w a1, (a1); \
  sc.w a4, a1, (a0); \
)

TEST_CASE( 5, a1, 1, \
  la a0, foo; \
  li a5, 0xdeadbeef; \
  sc.w a4, a5, (a0); \
  lr.w a1, (a0);
)




TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

coreid: .word 0
barrier: .word 0
foo: .word 1
.skip 1024
fooTest3: .word 0
RVTEST_DATA_END
