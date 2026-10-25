// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

package com.ultralytics.yolo

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import kotlin.math.roundToInt

/** Monocular metric-depth predictor shared by LiteRT GPU/CPU and ONNX Runtime QNN backends. */
class DepthEstimator(
    context: Context,
    modelPath: String,
    override var labels: List<String>,
    useGpu: Boolean = true,
) : BasePredictor() {
    private lateinit var floatInput: FloatArray
    private lateinit var inputBitmap: Bitmap
    private lateinit var intValues: IntArray
    private val outputShape: IntArray
    private val depthHeight: Int
    private val depthWidth: Int
    private var colorPixels = IntArray(0)

    /** Longest side of the block-mean grid emitted by the native depth stream. */
    var gridMaxDim: Int = DEFAULT_GRID_MAX_DIM

    init {
        YOLOFileUtils.loadModelLabels(context, modelPath)?.let { labels = it }
        val model = InferenceModel.create(context, modelPath, useGpu, "DepthEstimator")
        try {
            val inDims = model.inputDims
            val inHeight = if (inDims.size >= 4) inDims[1] else 640
            val inWidth = if (inDims.size >= 4) inDims[2] else 640
            inputSize = Size(inWidth, inHeight)
            modelInputSize = Pair(inWidth, inHeight)

            outputShape = model.outputDims.getOrNull(0) ?: IntArray(0)
            val channelFirst = outputShape.size >= 2 && outputShape.dropLast(2).all { it == 1 }
            val channelLast = outputShape.size == 4 && outputShape[0] == 1 && outputShape[3] == 1
            require(channelFirst || channelLast) {
                "Depth output tensor shape not supported: ${outputShape.joinToString()}"
            }
            depthHeight = if (channelLast) outputShape[1] else outputShape[outputShape.size - 2]
            depthWidth = if (channelLast) outputShape[2] else outputShape.last()
            require(depthWidth > 0 && depthHeight > 0 && depthWidth * depthHeight == model.outputElementCounts[0]) {
                "Invalid depth output tensor shape: ${outputShape.joinToString()}"
            }

            floatInput = FloatArray(inWidth * inHeight * 3)
            inputBitmap = Bitmap.createBitmap(inWidth, inHeight, Bitmap.Config.ARGB_8888)
            intValues = IntArray(inWidth * inHeight)
        } catch (t: Throwable) {
            model.close()
            throw t
        }
        rtModel = model
    }

    override fun predict(
        bitmap: Bitmap,
        origWidth: Int,
        origHeight: Int,
        rotateForCamera: Boolean,
        isLandscape: Boolean,
    ): YOLOResult {
        t0 = System.nanoTime()
        ImageUtils.prepareBitmapForModel(
            bitmap = bitmap,
            targetBitmap = inputBitmap,
            rotateForCamera = rotateForCamera,
            isLandscape = isLandscape,
            isFrontCamera = isFrontCamera,
            rotationDegrees = cameraRotationDegrees,
        )
        ImageUtils.copyRgbBitmapToFloatArray(
            inputBitmap,
            floatInput,
            intValues,
            channelsFirst = rtModel.inputUsesNchw,
        )

        val preEnd = System.nanoTime()
        val output = rtModel.run(floatInput)[0]
        val inferEnd = System.nanoTime()
        val depthMap = postProcessDepth(output, origWidth, origHeight)
        val timing = finishTiming(preEnd, inferEnd)
        return YOLOResult(
            origShape = Size(origWidth, origHeight),
            depthMap = depthMap,
            speed = timing.speedMs,
            fps = timing.fps,
            preMs = timing.preMs,
            inferenceMs = timing.inferenceMs,
            postMs = timing.postMs,
            accelerator = rtModel.accelerator,
            names = labels,
        )
    }

    internal fun postProcessDepth(output: FloatArray, origWidth: Int, origHeight: Int): DepthMap {
        require(output.size == depthWidth * depthHeight) {
            "Depth output size ${output.size} does not match ${depthWidth * depthHeight}"
        }
        val crop = modelMaskCropRect(depthWidth, depthHeight, origWidth, origHeight)
        val left = crop?.left ?: 0
        val top = crop?.top ?: 0
        val right = crop?.right ?: depthWidth
        val bottom = crop?.bottom ?: depthHeight
        val width = right - left
        val height = bottom - top
        require(width > 0 && height > 0) { "Invalid depth crop ${width}x$height" }

        val values = if (includeRawMaskData) FloatArray(width * height) else null
        if (values != null) {
            for (y in 0 until height) {
                val source = (y + top) * depthWidth
                output.copyInto(values, y * width, source + left, source + right)
            }
        }
        // The compact grid is always built (it costs one pass over the crop) so the native depth
        // stream never needs the dense copy above.
        val gridWidth = gridDim(width)
        val gridHeight = gridDim(height)
        val gridValues = blockMeanGrid(output, depthWidth, left, top, width, height, gridWidth, gridHeight)
        val size = width * height
        if (colorPixels.size != size) colorPixels = IntArray(size)
        val range = colorizeDepth(
            output, depthWidth, left, top, width, height, colorPixels, colors
        )
            ?: error("Depth output contains no valid values")

        return DepthMap(
            values = values,
            width = width,
            height = height,
            minDepth = range[0],
            maxDepth = range[1],
            image = Bitmap.createBitmap(colorPixels, width, height, Bitmap.Config.ARGB_8888),
            grid = gridValues,
            gridWidth = gridWidth,
            gridHeight = gridHeight,
        )
    }

    private fun gridDim(extent: Int): Int {
        val scale = gridMaxDim.coerceAtLeast(1).toFloat() / maxOf(extent, 1)
        return (extent * scale).roundToInt().coerceIn(1, extent.coerceAtLeast(1))
    }

    /**
     * Block means of [output]'s crop region, laid out row-major in a [gridWidth] x [gridHeight] grid.
     * Only finite samples inside [MIN_VALID_DEPTH_M]..[MAX_VALID_DEPTH_M] contribute; a block with no
     * valid sample is NaN. The grid spans exactly the crop, so it keeps the same upright/sensor
     * geometry the dense map had and existing box mapping stays valid.
     */
    private fun blockMeanGrid(
        output: FloatArray,
        depthWidth: Int,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        gridWidth: Int,
        gridHeight: Int,
    ): FloatArray {
        val grid = FloatArray(gridWidth * gridHeight)
        for (gy in 0 until gridHeight) {
            val y0 = top + gy * height / gridHeight
            val y1 = maxOf(y0 + 1, top + (gy + 1) * height / gridHeight)
            for (gx in 0 until gridWidth) {
                val x0 = left + gx * width / gridWidth
                val x1 = maxOf(x0 + 1, left + (gx + 1) * width / gridWidth)
                var sum = 0.0
                var count = 0
                for (y in y0 until y1) {
                    val row = y * depthWidth
                    for (x in x0 until x1) {
                        val value = output[row + x]
                        if (value.isFinite() && value >= MIN_VALID_DEPTH_M && value <= MAX_VALID_DEPTH_M) {
                            sum += value
                            count++
                        }
                    }
                }
                grid[gy * gridWidth + gx] = if (count == 0) Float.NaN else (sum / count).toFloat()
            }
        }
        return grid
    }

    private external fun colorizeDepth(
        output: FloatArray,
        depthWidth: Int,
        left: Int,
        top: Int,
        width: Int,
        height: Int,
        colorPixels: IntArray,
        colors: IntArray,
    ): FloatArray?

    companion object {
        const val DEFAULT_GRID_MAX_DIM = 96
        private const val MIN_VALID_DEPTH_M = 0.1f
        private const val MAX_VALID_DEPTH_M = 80f

        private val colors = IntArray(256).also { table ->
            val stops = arrayOf(
                intArrayOf(48, 18, 59),
                intArrayOf(50, 100, 200),
                intArrayOf(40, 190, 140),
                intArrayOf(245, 210, 60),
                intArrayOf(180, 20, 40),
            )
            for (index in table.indices) {
                val position = index.toFloat() / table.lastIndex * (stops.size - 1)
                val lower = position.toInt().coerceAtMost(stops.size - 2)
                val fraction = position - lower
                val first = stops[lower]
                val second = stops[lower + 1]
                table[index] = Color.rgb(
                    (first[0] + (second[0] - first[0]) * fraction).roundToInt(),
                    (first[1] + (second[1] - first[1]) * fraction).roundToInt(),
                    (first[2] + (second[2] - first[2]) * fraction).roundToInt(),
                )
            }
        }

        init {
            System.loadLibrary("ultralytics")
        }
    }
}
