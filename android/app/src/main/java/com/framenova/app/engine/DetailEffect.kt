package com.framenova.app.engine

import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram

/** Vignette and unsharp-mask sharpening in one GPU pass. Both strengths are 0..1. */
@UnstableApi
class DetailEffect(private val vignette: Float, private val sharpen: Float) : GlEffect {
    override fun toGlShaderProgram(context: Context, useHdr: Boolean): GlShaderProgram = DetailShaderProgram(useHdr, vignette, sharpen)
    override fun isNoOp(inputWidth: Int, inputHeight: Int): Boolean = vignette <= 0f && sharpen <= 0f
}

@UnstableApi
private class DetailShaderProgram(useHdr: Boolean, private val vignette: Float, private val sharpen: Float) :
    BaseGlShaderProgram(useHdr, 1) {
    private val program: GlProgram = try {
        GlProgram(VERTEX, FRAGMENT).apply { setBufferAttribute("aFramePosition", GlUtil.getNormalizedCoordinateBounds(), 4) }
    } catch (e: GlUtil.GlException) {
        throw VideoFrameProcessingException(e)
    }
    private var width = 1
    private var height = 1

    override fun configure(inputWidth: Int, inputHeight: Int): Size {
        width = inputWidth; height = inputHeight
        return Size(inputWidth, inputHeight)
    }

    override fun drawFrame(inputTexId: Int, presentationTimeUs: Long) {
        try {
            program.use()
            program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            program.setFloatUniform("uVignette", vignette)
            program.setFloatUniform("uSharpen", sharpen)
            program.setFloatsUniform("uTexelSize", floatArrayOf(1f / width, 1f / height))
            program.setFloatUniform("uAspect", width.toFloat() / height)
            program.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch (e: GlUtil.GlException) {
            throw VideoFrameProcessingException(e, presentationTimeUs)
        }
    }

    override fun release() {
        super.release()
        try { program.delete() } catch (e: GlUtil.GlException) { throw VideoFrameProcessingException(e) }
    }

    companion object {
        private const val VERTEX = """
            attribute vec4 aFramePosition;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aFramePosition;
                vTexCoord = aFramePosition.xy * 0.5 + 0.5;
            }
        """
        private const val FRAGMENT = """
            precision highp float;
            uniform sampler2D uTexSampler;
            uniform float uVignette;
            uniform float uSharpen;
            uniform vec2 uTexelSize;
            uniform float uAspect;
            varying vec2 vTexCoord;
            void main() {
                vec4 c = texture2D(uTexSampler, vTexCoord);
                if (uSharpen > 0.0) {
                    vec3 blur = texture2D(uTexSampler, vTexCoord + vec2(uTexelSize.x, 0.0)).rgb
                        + texture2D(uTexSampler, vTexCoord - vec2(uTexelSize.x, 0.0)).rgb
                        + texture2D(uTexSampler, vTexCoord + vec2(0.0, uTexelSize.y)).rgb
                        + texture2D(uTexSampler, vTexCoord - vec2(0.0, uTexelSize.y)).rgb;
                    blur *= 0.25;
                    c.rgb = clamp(c.rgb + (c.rgb - blur) * (uSharpen * 1.5), 0.0, 1.0);
                }
                if (uVignette > 0.0) {
                    vec2 d = (vTexCoord - 0.5) * vec2(uAspect, 1.0) / max(uAspect, 1.0);
                    float v = smoothstep(0.85, 0.2, length(d) * (0.9 + uVignette * 0.6));
                    c.rgb *= mix(1.0, v, uVignette);
                }
                gl_FragColor = c;
            }
        """
    }
}
