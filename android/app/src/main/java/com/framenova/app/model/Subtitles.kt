package com.framenova.app.model

/** A timed line of text: start, end (microseconds) and text. */
typealias Cue = Triple<Long, Long, String>

object Subtitles {
    private val srtTime = Regex("(\\d{1,2}):(\\d{2}):(\\d{2})[,.](\\d{1,3})")
    private val lrcTag = Regex("\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?]")

    fun parse(text: String, fileName: String = ""): List<Cue> {
        val clean = text.removePrefix("\uFEFF").replace("\r\n", "\n").replace('\r', '\n')
        return if (fileName.endsWith(".lrc", ignoreCase = true) || (lrcTag.containsMatchIn(clean) && !clean.contains("-->"))) parseLrc(clean)
        else parseSrt(clean)
    }

    fun parseSrt(text: String): List<Cue> = text.split(Regex("\n\\s*\n")).mapNotNull { block ->
        val lines = block.lines().map { it.trimEnd() }.filter { it.isNotEmpty() }
        val timing = lines.indexOfFirst { "-->" in it }
        if (timing < 0) return@mapNotNull null
        val (a, b) = lines[timing].split("-->").map { it.trim() }.takeIf { it.size == 2 } ?: return@mapNotNull null
        val start = srtUs(a) ?: return@mapNotNull null
        val end = srtUs(b) ?: return@mapNotNull null
        val body = lines.drop(timing + 1).joinToString("\n") { it.replace(Regex("<[^>]+>"), "") }.trim()
        if (body.isEmpty() || end <= start) null else Cue(start, end, body)
    }

    private fun srtUs(s: String): Long? {
        val m = srtTime.find(s) ?: return null
        val (h, mi, se, ms) = m.destructured
        val millis = ms.padEnd(3, '0').toLong()
        return ((h.toLong() * 3600 + mi.toLong() * 60 + se.toLong()) * 1000 + millis) * 1000
    }

    /** LRC lyrics: each line lasts until the next timestamp (the last one for 4 s). */
    fun parseLrc(text: String): List<Cue> {
        val stamped = mutableListOf<Pair<Long, String>>()
        for (line in text.lines()) {
            val tags = lrcTag.findAll(line).toList()
            if (tags.isEmpty()) continue
            val body = line.substring(tags.last().range.last + 1).replace(Regex("<\\d+:\\d+(?:\\.\\d+)?>"), "").trim()
            for (tag in tags) {
                val (m, s, frac) = tag.destructured
                val fracMs = if (frac.isEmpty()) 0L else frac.padEnd(3, '0').take(3).toLong()
                stamped += ((m.toLong() * 60 + s.toLong()) * 1000 + fracMs) * 1000 to body
            }
        }
        stamped.sortBy { it.first }
        return stamped.mapIndexedNotNull { i, (start, body) ->
            if (body.isEmpty()) return@mapIndexedNotNull null
            val end = stamped.getOrNull(i + 1)?.first ?: (start + 4_000_000)
            if (end <= start) null else Cue(start, end, body)
        }
    }

    fun toSrt(cues: List<Cue>): String = cues.mapIndexed { i, (s, e, t) -> "${i + 1}\n${fmt(s)} --> ${fmt(e)}\n$t\n" }.joinToString("\n")

    private fun fmt(us: Long): String {
        val ms = us / 1000
        return "%02d:%02d:%02d,%03d".format(ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }
}
