package dev.milanko.dart_pdf_editor_app

import android.app.Activity
import android.content.Context
import android.hardware.input.InputManager
import android.os.Build
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.EventChannel

/// Preview-style trackpad signatures on Android (`PlatformTrackpadSignature
/// Capture` in app/lib/trackpad_signature.dart).
///
/// A touchpad normally only drives the pointer, but under pointer capture
/// (API 26) it reports raw `SOURCE_TOUCHPAD` contacts with absolute
/// positions on the pad - exactly the finger-on-the-surface signal a
/// signature needs. While Dart listens, this captures the pointer on the
/// Flutter view (which also hides it and keeps it still) and streams the first
/// finger down, normalized by the device's motion ranges with y down, until it
/// lifts. Captured mouse/click events are swallowed. Keys still reach Flutter,
/// where the pad ends the capture; losing capture (focus change, the system
/// revoking it) finishes it from here.
class TrackpadSignatureCapture(private val activity: Activity) :
    EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var view: View? = null
    private var drawingPointer = NO_POINTER

    companion object {
        private const val NO_POINTER = -1

        /// Whether a physical touchpad is attached.
        fun isAvailable(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
            val inputManager =
                context.getSystemService(Context.INPUT_SERVICE) as InputManager
            return inputManager.inputDeviceIds.any { id ->
                val device = inputManager.getInputDevice(id)
                device != null && !device.isVirtual &&
                    device.supportsSource(InputDevice.SOURCE_TOUCHPAD)
            }
        }

        private fun findFlutterView(view: View): FlutterView? {
            if (view is FlutterView) return view
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) {
                    findFlutterView(view.getChildAt(i))?.let { return it }
                }
            }
            return null
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        val target = findFlutterView(activity.window.decorView)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O || target == null) {
            events.endOfStream()
            return
        }
        sink = events
        view = target
        target.setOnCapturedPointerListener { _, event -> onCaptured(event) }
        target.requestPointerCapture()
    }

    override fun onCancel(arguments: Any?) = stop()

    /// Forwarded from `Activity.onPointerCaptureChanged`.
    fun onPointerCaptureChanged(hasCapture: Boolean) {
        if (!hasCapture && sink != null) finish()
    }

    private fun finish() {
        val events = sink
        stop()
        events?.success(mapOf("phase" to "finish"))
        events?.endOfStream()
    }

    /// Idempotent: releases the capture and the listener.
    fun stop() {
        sink = null
        drawingPointer = NO_POINTER
        val captured = view ?: return
        view = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            captured.setOnCapturedPointerListener(null)
            captured.releasePointerCapture()
        }
    }

    private fun onCaptured(event: MotionEvent): Boolean {
        // Everything captured is consumed; only touchpad contacts draw.
        if (!event.isFromSource(InputDevice.SOURCE_TOUCHPAD)) return true
        val device = event.device ?: return true
        val rangeX = device.getMotionRange(MotionEvent.AXIS_X, event.source)
        val rangeY = device.getMotionRange(MotionEvent.AXIS_Y, event.source)
        if (rangeX == null || rangeY == null) return true

        fun emit(phase: String, x: Float, y: Float) {
            sink?.success(
                mapOf(
                    "phase" to phase,
                    "x" to normalize(x, rangeX.min, rangeX.range),
                    "y" to normalize(y, rangeY.min, rangeY.range),
                ),
            )
        }

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (drawingPointer == NO_POINTER) {
                    val index = event.actionIndex
                    drawingPointer = event.getPointerId(index)
                    emit("down", event.getX(index), event.getY(index))
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val index = event.findPointerIndex(drawingPointer)
                if (index >= 0) {
                    for (h in 0 until event.historySize) {
                        emit(
                            "move",
                            event.getHistoricalX(index, h),
                            event.getHistoricalY(index, h),
                        )
                    }
                    emit("move", event.getX(index), event.getY(index))
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val index = event.actionIndex
                if (event.getPointerId(index) == drawingPointer) {
                    emit("up", event.getX(index), event.getY(index))
                    drawingPointer = NO_POINTER
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                val index = event.findPointerIndex(drawingPointer)
                if (index >= 0) {
                    emit("up", event.getX(index), event.getY(index))
                }
                drawingPointer = NO_POINTER
            }
        }
        return true
    }

    private fun normalize(value: Float, min: Float, range: Float): Double =
        if (range <= 0f) 0.0 else ((value - min) / range).toDouble().coerceIn(0.0, 1.0)
}
