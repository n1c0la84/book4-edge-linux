# SPDX-License-Identifier: GPL-2.0-only
"""Offline checks for false-success cases in the experiment report."""
import contextlib
import importlib.util
import io
import pathlib
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("summarize", pathlib.Path(__file__).with_name("summarize.py"))
summary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(summary)

PROBE = """format=1 state=0x0200c354 counter_hz=1000000 sample_every=256 loops=1 loop_ticks=30000000 smc_nmissed=0 smc_kp_nmissed=0 loop_nmissed=0 loop_kp_nmissed=0
cpu=0 entered=256 returned=256 sampled=1 zero_ticks=0 backwards=0 migrated=0 first_tick=1000 last_tick=30001000 total_ticks=2560 min_ticks=10 max_ticks=10 pre_none_enabled=1 post_none_enabled=0
return cpu=0 code=0 count=254
return cpu=0 code=-1 count=1
return cpu=0 code=-3 count=1
hist cpu=0 sampled=0 fls_ticks=4 count=255
hist cpu=0 sampled=1 fls_ticks=4 count=1
"""


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for phase, success in (("before", 4), ("after", 5)):
            dest = self.root / phase
            dest.mkdir()
            for name in ("aosd", "cxsd", "ddr"):
                (dest / f"{name}.txt").write_text("Count: 0\n")
            (dest / "system-domain.txt").write_text(f"State Time Usage Rejected Above Below S2idle\nS0 0 0 0 0 0 {success}\n")
            (dest / "suspend-counts.txt").write_text(f"{success}\n0\n")
        (self.root / "metadata.txt").write_text("mode=sampled\n")
        (self.root / "start-wall.txt").write_text("1000.0")
        (self.root / "end-wall.txt").write_text("1032.0")
        (self.root / "probe.txt").write_text(PROBE)

    def run_report(self):
        text = io.StringIO()
        with contextlib.redirect_stdout(text):
            result = summary.report(self.root)
        return result, text.getvalue()

    def test_raw_psci_errno_is_not_linux_errno(self):
        result, output = self.run_report()
        self.assertFalse(result)
        self.assertIn("-1 (NOT_SUPPORTED)", output)
        self.assertIn("-3 (DENIED)", output)
        self.assertIn("30.000000 s", output)

    def test_missing_probe_is_not_mislabelled_baseline(self):
        (self.root / "probe.txt").unlink()
        result, output = self.run_report()
        self.assertTrue(result)
        self.assertIn("Missing probe report", output)

    def test_dropped_events_invalidate_report(self):
        (self.root / "probe.txt").write_text(PROBE.replace("smc_nmissed=0", "smc_nmissed=2"))
        self.assertTrue(self.run_report()[0])

    def test_unpaired_returns_invalidate_report(self):
        (self.root / "probe.txt").write_text(PROBE.replace("entered=256", "entered=257"))
        self.assertTrue(self.run_report()[0])

    def test_failed_suspend_invalidate_report(self):
        (self.root / "after/suspend-counts.txt").write_text("4\n1\n")
        self.assertTrue(self.run_report()[0])

    def test_frozen_counter_invalidate_report(self):
        (self.root / "probe.txt").write_text(PROBE.replace("loop_ticks=30000000", "loop_ticks=0"))
        self.assertTrue(self.run_report()[0])

    def test_baseline(self):
        (self.root / "metadata.txt").write_text("mode=baseline\n")
        (self.root / "probe.txt").unlink()
        self.assertFalse(self.run_report()[0])


if __name__ == "__main__":
    unittest.main()
