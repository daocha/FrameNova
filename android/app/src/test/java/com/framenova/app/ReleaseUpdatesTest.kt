package com.framenova.app

import com.framenova.app.update.ReleaseUpdates
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReleaseUpdatesTest {
    private fun release(tag: String, apk: String, sums: String, url: String = "https://github.com/daocha/FrameNova/releases/download/$tag/") = JSONObject(
        """{"tag_name":"$tag","draft":false,"prerelease":false,"assets":[
            {"name":"$apk","size":1234,"browser_download_url":"$url$apk"},
            {"name":"$sums","size":90,"browser_download_url":"$url$sums"}]}"""
    )

    @Test fun selectsNewerRelease() {
        val r = ReleaseUpdates.select(release("v0.2.0", "FrameNova-0.2.0-2.apk", "FrameNova-0.2.0-2.SHA256SUMS"), 1)!!
        assertEquals("0.2.0", r.version)
        assertEquals(2L, r.versionCode)
    }

    @Test fun ignoresOlderOrForeignReleases() {
        assertNull(ReleaseUpdates.select(release("v0.2.0", "FrameNova-0.2.0-2.apk", "FrameNova-0.2.0-2.SHA256SUMS"), 2))
        assertNull(ReleaseUpdates.select(release("v0.2.0", "FrameNova-0.2.0-2.apk", "FrameNova-0.2.0-2.SHA256SUMS", "https://example.com/x/"), 1))
        assertNull(ReleaseUpdates.select(release("v0.3.0", "FrameNova-0.2.0-2.apk", "FrameNova-0.2.0-2.SHA256SUMS"), 1))
    }

    @Test fun selectsLanBuild() {
        val json = JSONObject("""{"versionCode":500,"versionName":"0.1.0-debug","apk":"FrameNova-debug-500.apk","size":42}""")
        val r = ReleaseUpdates.selectLan(json, 499, "http://192.168.1.2:8767/")!!
        assertEquals("http://192.168.1.2:8767/FrameNova-debug-500.apk", r.apkUrl)
        assertNull(ReleaseUpdates.selectLan(json, 500, "http://192.168.1.2:8767/"))
    }

    @Test fun readsChecksums() {
        val sha = "a".repeat(64)
        assertEquals(sha, ReleaseUpdates.checksum("$sha  FrameNova-debug-5.apk\n", "FrameNova-debug-5.apk"))
        assertNull(ReleaseUpdates.checksum("$sha  other.apk\n", "FrameNova-debug-5.apk"))
    }
}
