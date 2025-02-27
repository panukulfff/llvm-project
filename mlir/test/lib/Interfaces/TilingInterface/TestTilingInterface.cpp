//===- TestTilingInterface.cpp - Test tiling using `TilingInterface` -----===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file implements a pass for testing tiling operations using
// `TilingInterface`.
//
//===----------------------------------------------------------------------===//

#include <utility>

#include "mlir/Dialect/Affine/IR/AffineOps.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Linalg/Transforms/TilingInterfaceImpl.h"
#include "mlir/Dialect/Linalg/Transforms/Transforms.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/TileUsingInterface.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/Dialect/Tensor/IR/TensorTilingInterfaceImpl.h"
#include "mlir/Interfaces/TilingInterface.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;

namespace {

/// Pattern for testing `TileUsingSCFForOp` pattern (that tiles operations using
/// the `TilingInterface` with `scf.for` ops for iterating over the tiles) while
/// using a `filter` to avoid recursive application.
struct TestTileUsingSCFForOp
    : public OpInterfaceRewritePattern<TilingInterface> {
  TestTileUsingSCFForOp(MLIRContext *context, scf::SCFTilingOptions options,
                        linalg::LinalgTransformationFilter filter =
                            linalg::LinalgTransformationFilter(),
                        PatternBenefit benefit = 1)
      : OpInterfaceRewritePattern<TilingInterface>(context, benefit),
        options(std::move(options)), filter(std::move(filter)) {}

  /// Construct a generic pattern applied to `opName`.
  TestTileUsingSCFForOp(StringRef opName, MLIRContext *context,
                        scf::SCFTilingOptions options,
                        linalg::LinalgTransformationFilter filter =
                            linalg::LinalgTransformationFilter(),
                        PatternBenefit benefit = 1)
      : OpInterfaceRewritePattern<TilingInterface>(context, benefit),
        options(std::move(options)), filter(std::move(filter)) {}

  LogicalResult matchAndRewrite(TilingInterface op,
                                PatternRewriter &rewriter) const override {
    if (failed(filter.checkAndNotify(rewriter, op)))
      return failure();

    FailureOr<scf::SCFTilingResult> tilingResult =
        scf::tileUsingSCFForOp(rewriter, op, options);
    if (failed(tilingResult))
      return rewriter.notifyMatchFailure(op, "failed to tile operation");

    if (op->getNumResults()) {
      rewriter.replaceOp(op, tilingResult->replacements);
    } else {
      rewriter.eraseOp(op);
    }

    filter.replaceLinalgTransformationFilter(rewriter, tilingResult->tiledOp);
    return success();
  }

private:
  scf::SCFTilingOptions options;
  linalg::LinalgTransformationFilter filter;
};

/// Pattern for testing `TileConsumerAndFuseProducersUsingSCFForOp` pattern
/// (that tiles and fuses operations using the `TilingInterface` with `scf.for`
/// ops for iterating over the tiles) while using a `filter` to avoid recursive
/// application.
struct TestTileConsumerAndFuseProducersGreedilyUsingSCFForOp
    : public OpInterfaceRewritePattern<TilingInterface> {
  TestTileConsumerAndFuseProducersGreedilyUsingSCFForOp(
      MLIRContext *context, scf::SCFTileAndFuseOptions options,
      linalg::LinalgTransformationFilter filter =
          linalg::LinalgTransformationFilter(),
      PatternBenefit benefit = 1)
      : OpInterfaceRewritePattern<TilingInterface>(context, benefit),
        options(std::move(options)), filter(std::move(filter)) {}

  /// Construct a generic pattern applied to `opName`.
  TestTileConsumerAndFuseProducersGreedilyUsingSCFForOp(
      StringRef opName, MLIRContext *context,
      scf::SCFTileAndFuseOptions options,
      linalg::LinalgTransformationFilter filter =
          linalg::LinalgTransformationFilter(),
      PatternBenefit benefit = 1)
      : OpInterfaceRewritePattern<TilingInterface>(context, benefit),
        options(std::move(options)), filter(std::move(filter)) {}

  LogicalResult matchAndRewrite(TilingInterface op,
                                PatternRewriter &rewriter) const override {
    if (failed(filter.checkAndNotify(rewriter, op)))
      return failure();

    FailureOr<scf::SCFTileAndFuseResult> tileAndFuseResult =
        scf::tileConsumerAndFuseProducerGreedilyUsingSCFForOp(rewriter, op,
                                                              options);
    if (failed(tileAndFuseResult)) {
      return failure();
    }
    // Replace the tiled op with replacements.
    SmallVector<Value> replacements(op->getNumResults());
    for (const auto &result : llvm::enumerate(op->getResults())) {
      replacements[result.index()] =
          tileAndFuseResult->replacements.lookup(result.value());
    }
    rewriter.replaceOp(op, replacements);

    filter.replaceLinalgTransformationFilter(
        rewriter, tileAndFuseResult->tiledAndFusedOps.front());
    return success();
  }

private:
  scf::SCFTileAndFuseOptions options;
  linalg::LinalgTransformationFilter filter;
};

/// Pattern to lower operations that implement the `TilingInterface` to
/// loops/scalar IR using `scf.for`.
struct LowerToLoopsUsingSCFForOp
    : public OpInterfaceRewritePattern<TilingInterface> {
  using OpInterfaceRewritePattern<TilingInterface>::OpInterfaceRewritePattern;

  /// `matchAndRewrite` implementation that returns the significant transformed
  /// pieces of IR.
  LogicalResult matchAndRewrite(TilingInterface op,
                                PatternRewriter &rewriter) const override {
    FailureOr<SmallVector<scf::ForOp>> loops =
        scf::lowerToLoopsUsingSCFForOp(rewriter, op);
    if (failed(loops))
      return rewriter.notifyMatchFailure(op, "failed to lower to loops");
    rewriter.eraseOp(op);
    return loops;
  }
};

/// Test pass for testing the use of `TilingInterface`.
struct TestTilingInterfacePass
    : public PassWrapper<TestTilingInterfacePass, OperationPass<func::FuncOp>> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(TestTilingInterfacePass)

  TestTilingInterfacePass() = default;
  TestTilingInterfacePass(const TestTilingInterfacePass &pass)
      : PassWrapper(pass) {}
  void getDependentDialects(DialectRegistry &registry) const override {
    registry.insert<AffineDialect, linalg::LinalgDialect, memref::MemRefDialect,
                    scf::SCFDialect, tensor::TensorDialect>();
    linalg::registerTilingInterfaceExternalModels(registry);
    tensor::registerTilingInterfaceExternalModels(registry);
  }
  StringRef getArgument() const final { return "test-tiling-interface"; }
  StringRef getDescription() const final {
    return "Test tiling using TilingInterface";
  }

  Option<bool> testTiling{
      *this, "tile-using-scf-for",
      llvm::cl::desc(
          "Test tiling using TilingInterface with scf.for operations"),
      llvm::cl::init(false)};

  Option<bool> testTileConsumerAndFuseProducer{
      *this, "tile-consumer-and-fuse-producer-using-scf-for",
      llvm::cl::desc("Test tile and fuse transformation using TilingInterface "
                     "with scf.for operations"),
      llvm::cl::init(false)};

  Option<bool> testLoweringToScalar{
      *this, "lower-to-scalar-using-scf-for",
      llvm::cl::desc("Test lowering to scalar implementation using "
                     "TilingInterface with scf.for operations"),
      llvm::cl::init(false)};

  void runOnOperation() override;

private:
  void addTestPatterns(MLIRContext *context, RewritePatternSet &patterns);
};
} // namespace

static void addPatternForTiling(MLIRContext *context,
                                RewritePatternSet &patterns,
                                StringRef filterName,
                                ArrayRef<int64_t> tileSizes,
                                ArrayRef<unsigned> interchange = {}) {
  scf::SCFTilingOptions tilingOptions;
  tilingOptions.setTileSizes(tileSizes).setInterchange(interchange);
  linalg::LinalgTransformationFilter filter(
      StringAttr::get(context, filterName), StringAttr::get(context, "tiled"));
  patterns.add<TestTileUsingSCFForOp>(context, tilingOptions, filter);
}

static void addPatternForTileAndFuse(MLIRContext *context,
                                     RewritePatternSet &patterns,
                                     StringRef filterName,
                                     ArrayRef<int64_t> tileSizes,
                                     ArrayRef<unsigned> interchange = {}) {
  scf::SCFTileAndFuseOptions tileAndFuseOptions;
  tileAndFuseOptions.tilingOptions.setTileSizes(tileSizes).setInterchange(
      interchange);
  linalg::LinalgTransformationFilter filter(
      StringAttr::get(context, filterName), StringAttr::get(context, "tiled"));
  patterns.add<TestTileConsumerAndFuseProducersGreedilyUsingSCFForOp>(
      context, tileAndFuseOptions, filter);
}

void TestTilingInterfacePass::addTestPatterns(MLIRContext *context,
                                              RewritePatternSet &patterns) {
  if (testTiling) {
    // 1. Tiling M and N dims of `linalg.matmul` on tensors.
    addPatternForTiling(context, patterns, "simple_gemm", {10, 20});
    // 2. Tiling M, N and K of `linalg.matmul` on buffers.
    addPatternForTiling(context, patterns, "simple_gemm_memref", {10, 20, 30});
    // 3. Tiling 3D parallel generic op which implements a transpose
    addPatternForTiling(context, patterns, "parallel_generic_transpose",
                        {10, 0, 20});
    // 4. Tiling 2D conv op.
    addPatternForTiling(context, patterns, "simple_conv",
                        {0, 0, 0, 0, 10, 20, 30});
    // 5. Tiling a simple op with `linalg.index` inside.
    addPatternForTiling(context, patterns, "indexed_semantics", {10, 20});
    // 6. Tiling + interchange of an operation
    addPatternForTiling(context, patterns, "gemm_interchange", {10, 20, 30},
                        {1, 2, 0});
    // 7. Tiling for 2D pad tensor operations.
    addPatternForTiling(context, patterns, "pad_2dtiling", {2, 3});
    // 8. Tiling inner dimension of 2d pad tensor operations.
    addPatternForTiling(context, patterns, "pad_inner_tiling", {0, 3});
    // 9. Tiling inner dimension of 2d pad tensor operations.
    addPatternForTiling(context, patterns, "pad_outer_tiling", {2, 3});

    return;
  }
  if (testTileConsumerAndFuseProducer) {
    // 1. Tile and fuse of gemm with fill producer and bias-add consumer.
    addPatternForTileAndFuse(context, patterns, "fusion", {10, 20});
    // 2. Tile and fuse sequence of GEMMs, by fusing only along M.
    addPatternForTileAndFuse(context, patterns, "gemm_fusion", {10});
    // 3. Tile and fuse gemm with consumer + interchange of tiled loops.
    addPatternForTileAndFuse(context, patterns, "gemm_interchange_fusion",
                             {10, 20}, {1, 0});
    // 4. Tile and fuse matmul + transpose(matmul). Will introduce redundant
    // computations.
    addPatternForTileAndFuse(context, patterns, "gemm_plus_gemm_fusion",
                             {10, 20});
    // 5. Tile and fuse a sequence of GEMMs by tiling and fusing only along M
    // dimension.
    addPatternForTileAndFuse(context, patterns, "gemm_sequence_fusion", {10});
    return;
  }
  if (testLoweringToScalar) {
    patterns.add<LowerToLoopsUsingSCFForOp>(context);
  }
}

void TestTilingInterfacePass::runOnOperation() {
  MLIRContext *context = &getContext();

  RewritePatternSet tilingPatterns(context);
  addTestPatterns(context, tilingPatterns);
  if (failed(applyPatternsAndFoldGreedily(getOperation(),
                                          std::move(tilingPatterns))))
    return signalPassFailure();
}

namespace mlir {
namespace test {
void registerTestTilingInterface() {
  PassRegistration<TestTilingInterfacePass>();
}
} // namespace test
} // namespace mlir
