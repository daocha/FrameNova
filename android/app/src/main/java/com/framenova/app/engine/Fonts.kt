package com.framenova.app.engine

import android.content.Context
import android.graphics.Typeface
import androidx.core.content.res.ResourcesCompat
import com.framenova.app.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap

enum class FontGroup { SYSTEM, LATIN, ART, CHINESE }

/**
 * A font: bundled ([resId]), downloaded on demand from the Google Fonts repository ([remotePath]), or a system face.
 * Every bundled and downloadable font is licensed under the SIL Open Font License 1.1.
 */
data class FontDef(
    val id: String,
    val name: String,
    val group: FontGroup,
    val resId: Int? = null,
    val remotePath: String? = null,
    val sizeMb: Int = 0,
    val variable: Boolean = false,
    val sample: String = "Aa",
)

object FontCatalog {
    private const val BASE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"

    val all: List<FontDef> = listOf(
        FontDef("system", "System Sans", FontGroup.SYSTEM, sample = "Aa 字"),
        FontDef("system_serif", "System Serif", FontGroup.SYSTEM, sample = "Aa 字"),
        FontDef("system_mono", "System Mono", FontGroup.SYSTEM),
        FontDef("inter", "Inter", FontGroup.LATIN, R.font.inter, variable = true),
        FontDef("montserrat", "Montserrat", FontGroup.LATIN, R.font.montserrat, variable = true),
        FontDef("oswald", "Oswald", FontGroup.LATIN, R.font.oswald, variable = true),
        FontDef("bebas_neue", "Bebas Neue", FontGroup.LATIN, R.font.bebas_neue),
        FontDef("playfair_display", "Playfair Display", FontGroup.LATIN, R.font.playfair_display, variable = true),
        FontDef("roboto_mono", "Roboto Mono", FontGroup.LATIN, R.font.roboto_mono, variable = true),
        FontDef("pacifico", "Pacifico", FontGroup.LATIN, R.font.pacifico),
        FontDef("lobster", "Lobster", FontGroup.LATIN, R.font.lobster),
        FontDef("dancing_script", "Dancing Script", FontGroup.LATIN, R.font.dancing_script, variable = true),
        FontDef("caveat", "Caveat", FontGroup.LATIN, R.font.caveat, variable = true),
        // Display and art styles.
        FontDef("bangers", "Bangers", FontGroup.ART, R.font.bangers),
        FontDef("lilita_one", "Lilita One", FontGroup.ART, R.font.lilita_one),
        FontDef("fredoka", "Fredoka", FontGroup.ART, R.font.fredoka, variable = true),
        FontDef("righteous", "Righteous", FontGroup.ART, R.font.righteous),
        FontDef("bungee", "Bungee", FontGroup.ART, R.font.bungee),
        FontDef("rubik_mono_one", "Rubik Mono One", FontGroup.ART, R.font.rubik_mono_one),
        FontDef("shrikhand", "Shrikhand", FontGroup.ART, R.font.shrikhand),
        FontDef("abril_fatface", "Abril Fatface", FontGroup.ART, R.font.abril_fatface),
        FontDef("alfa_slab_one", "Alfa Slab One", FontGroup.ART, R.font.alfa_slab_one),
        FontDef("cinzel_decorative", "Cinzel Decorative", FontGroup.ART, R.font.cinzel_decorative),
        FontDef("rye", "Rye", FontGroup.ART, R.font.rye),
        FontDef("black_ops_one", "Black Ops One", FontGroup.ART, R.font.black_ops_one),
        FontDef("creepster", "Creepster", FontGroup.ART, R.font.creepster),
        FontDef("monoton", "Monoton", FontGroup.ART, R.font.monoton),
        FontDef("neonderthaw", "Neonderthaw", FontGroup.ART, R.font.neonderthaw),
        FontDef("audiowide", "Audiowide", FontGroup.ART, R.font.audiowide),
        FontDef("orbitron", "Orbitron", FontGroup.ART, R.font.orbitron, variable = true),
        FontDef("press_start_2p", "Press Start 2P", FontGroup.ART, R.font.press_start_2p),
        FontDef("silkscreen", "Silkscreen", FontGroup.ART, R.font.silkscreen),
        FontDef("great_vibes", "Great Vibes", FontGroup.ART, R.font.great_vibes),
        FontDef("sacramento", "Sacramento", FontGroup.ART, R.font.sacramento),
        FontDef("kaushan_script", "Kaushan Script", FontGroup.ART, R.font.kaushan_script),
        FontDef("amatic_sc", "Amatic SC", FontGroup.ART, R.font.amatic_sc),
        FontDef("indie_flower", "Indie Flower", FontGroup.ART, R.font.indie_flower),
        FontDef("noto_sans_tc", "思源黑體 Noto Sans TC", FontGroup.CHINESE, remotePath = "notosanstc/NotoSansTC%5Bwght%5D.ttf", sizeMb = 12, variable = true, sample = "繁體字"),
        FontDef("noto_serif_tc", "思源宋體 Noto Serif TC", FontGroup.CHINESE, remotePath = "notoseriftc/NotoSerifTC%5Bwght%5D.ttf", sizeMb = 17, variable = true, sample = "繁體字"),
        FontDef("chiron_hei_hk", "昭源黑體 Chiron Hei HK", FontGroup.CHINESE, remotePath = "chironheihk/ChironHeiHK%5Bwght%5D.ttf", sizeMb = 31, variable = true, sample = "香港字"),
        FontDef("chiron_sung_hk", "昭源宋體 Chiron Sung HK", FontGroup.CHINESE, remotePath = "chironsunghk/ChironSungHK%5Bwght%5D.ttf", sizeMb = 51, variable = true, sample = "香港字"),
        FontDef("lxgw_wenkai_tc", "霞鶩文楷 LXGW WenKai TC", FontGroup.CHINESE, remotePath = "lxgwwenkaitc/LXGWWenKaiTC-Regular.ttf", sizeMb = 13, sample = "文楷字"),
        FontDef("iansui", "芫荽 Iansui", FontGroup.CHINESE, remotePath = "iansui/Iansui-Regular.ttf", sizeMb = 9, sample = "芫荽字"),
        FontDef("huninn", "粉圓 Huninn", FontGroup.CHINESE, remotePath = "huninn/Huninn-Regular.ttf", sizeMb = 5, sample = "粉圓字"),
        FontDef("lxgw_marker_gothic", "霞鶩漫黑 LXGW Marker Gothic", FontGroup.CHINESE, remotePath = "lxgwmarkergothic/LXGWMarkerGothic-Regular.ttf", sizeMb = 3, sample = "漫黑字"),
        FontDef("chiron_goround_tc", "昭源圓體 Chiron GoRound TC", FontGroup.CHINESE, remotePath = "chirongoroundtc/ChironGoRoundTC%5Bwght%5D.ttf", sizeMb = 51, variable = true, sample = "圓體字"),
        FontDef("cactus_classical_serif", "仙人掌明體 Cactus Classical Serif", FontGroup.CHINESE, remotePath = "cactusclassicalserif/CactusClassicalSerif-Regular.ttf", sizeMb = 29, sample = "明體字"),
    ).map { if (it.remotePath != null) it.copy(remotePath = BASE + it.remotePath) else it }

    fun byId(id: String): FontDef = all.firstOrNull { it.id == id } ?: all.first()
}

/** Loads typefaces for UI and rendering threads alike. Call [init] once from the Application. */
object FontManager {
    private lateinit var appContext: Context
    private val cache = ConcurrentHashMap<String, Typeface>()

    fun init(context: Context) { appContext = context.applicationContext }

    private fun fileFor(def: FontDef): File = File(File(appContext.filesDir, "fonts"), "${def.id}.ttf")

    fun isAvailable(id: String): Boolean {
        val def = FontCatalog.byId(id)
        return def.remotePath == null || fileFor(def).isFile
    }

    /** The typeface for [id]; falls back to the system face while a downloadable font is missing. */
    fun typeface(id: String): Typeface {
        cache[id]?.let { return it }
        val def = FontCatalog.byId(id)
        val tf = try {
            when {
                def.id == "system_serif" -> Typeface.SERIF
                def.id == "system_mono" -> Typeface.MONOSPACE
                def.resId != null -> ResourcesCompat.getFont(appContext, def.resId)
                def.remotePath != null && fileFor(def).isFile -> Typeface.createFromFile(fileFor(def))
                else -> null
            }
        } catch (_: Exception) { null } ?: return Typeface.DEFAULT
        cache[id] = tf
        return tf
    }

    fun isVariable(id: String): Boolean = FontCatalog.byId(id).variable

    suspend fun download(id: String, progress: (Float) -> Unit) = withContext(Dispatchers.IO) {
        val def = FontCatalog.byId(id)
        val url = def.remotePath ?: return@withContext
        val target = fileFor(def)
        target.parentFile?.mkdirs()
        val part = File(target.parentFile, "${target.name}.part")
        var next = URL(url)
        var connection: HttpURLConnection? = null
        repeat(5) {
            val c = (next.openConnection() as HttpURLConnection).apply {
                connectTimeout = 15_000; readTimeout = 30_000; instanceFollowRedirects = false
            }
            if (c.responseCode in 300..399) {
                next = URL(next, c.getHeaderField("Location") ?: throw IOException("Bad redirect")); c.disconnect()
            } else { connection = c; return@repeat }
        }
        val conn = connection ?: throw IOException("Too many redirects")
        try {
            if (conn.responseCode != HttpURLConnection.HTTP_OK) throw IOException("Font download failed (${conn.responseCode})")
            val total = conn.contentLengthLong.takeIf { it > 0 } ?: (def.sizeMb * 1_000_000L)
            var read = 0L
            part.outputStream().buffered().use { out ->
                conn.inputStream.buffered().use { input ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        read += n
                        progress((read.toFloat() / total).coerceIn(0f, 1f))
                    }
                }
            }
            // Validate before use: a truncated font would crash text rendering later.
            Typeface.createFromFile(part).also { if (it == Typeface.DEFAULT) throw IOException("Invalid font file") }
            if (!part.renameTo(target)) throw IOException("Could not save font")
            cache.remove(id)
        } finally {
            conn.disconnect()
            part.delete()
        }
    }
}
