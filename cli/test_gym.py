"""Tests for the gym CLI.

Runs against a fixture snapshot rather than the real one, so the suite works on
a machine that has never seen the phone.

    python3 -m unittest discover cli
"""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
gym = __import__("importlib").machinery.SourceFileLoader("gym", str(HERE / "gym")).load_module()

FIXTURE = {
    "schema": 4,
    "generated_at": "2026-08-20T13:12:47Z",
    "app_version": "0.1.0",
    "body_weight": {
        "unit": "lb", "current": 176.4, "current_date": "2026-08-20",
        "change_30d": -1.8, "trend_per_week": -0.4,
        "history": [{"date": "2026-07-21", "lb": 179.6},
                    {"date": "2026-08-10", "lb": 177.9},
                    {"date": "2026-08-20", "lb": 176.4}],
    },
    "today": {
        "date": "2026-08-20", "day": "Push A",
        "sets_done": 7, "sets_planned": 20,
        "exercises_done": 2, "exercises_planned": 3,
        "volume": 9420,
        "items": [
            {"slug": "bench-press", "name": "Bench Press", "target_sets": 4,
             "target_reps": 8, "target_weight": 185, "rest_seconds": 150,
             "sets_done": 4, "warmup_sets": 1, "done": True, "volume": 5365,
             "performed": [{"weight": 135, "reps": 10, "kind": "warmup"}]
                          + [{"weight": 185, "reps": r, "kind": "working", "rpe": 8.5}
                             for r in (8, 8, 7, 6)]},
            {"slug": "cable-fly", "name": "Cable Fly", "target_sets": 3,
             "target_reps": 12, "target_weight": 30, "rest_seconds": 60,
             "sets_done": 3, "warmup_sets": 0, "done": True, "volume": 1080,
             "performed": [{"weight": 30, "reps": 12, "kind": "working"}] * 3},
            {"slug": "lateral-raise", "name": "Lateral Raise", "target_sets": 3,
             "target_reps": 15, "target_weight": 20, "rest_seconds": 60,
             "sets_done": 0, "warmup_sets": 0, "done": False, "volume": 0,
             "performed": []},
            {"slug": "treadmill", "name": "Treadmill", "target_sets": 1,
             "target_reps": 0, "target_weight": 0, "rest_seconds": 0,
             "sets_done": 0, "warmup_sets": 0, "done": True, "volume": 0,
             "modality": "cardio",
             "cardio_target": {"seconds": 1200, "incline": 3.0},
             "cardio": {"bouts": 1, "seconds": 1500, "distance": 2.1,
                        "average_incline": 3.0, "average_speed": 5.04},
             "performed": [{"weight": 0, "reps": 0, "kind": "working",
                            "seconds": 1500, "distance": 2.1, "incline": 3.0}]},
        ],
    },
    "exercises": [
        {"slug": "bench-press", "name": "Bench Press", "loading": "barbell",
         "working_weight": 185, "last_performed": "2026-08-19",
         "best": {"weight": 185, "reps": 8, "date": "2026-08-19"},
         "change_30d": 12.5,
         "primary_muscle": "chest", "secondary_muscles": ["triceps", "shoulders"],
         "recent": [{"date": "2026-08-19", "top_weight": 185, "reps": [8, 8, 7, 6],
                     "volume": 5365, "warmup_sets": 1, "average_rpe": 8.5},
                    {"date": "2026-08-12", "top_weight": 182.5, "reps": [8, 7, 7, 6],
                     "volume": 5110, "warmup_sets": 0, "average_rpe": None}]},
        {"slug": "deadlift", "name": "Deadlift", "loading": "barbell",
         "working_weight": 315, "last_performed": "2026-08-17",
         "change_30d": None, "primary_muscle": "back",
         "secondary_muscles": ["hamstrings"], "recent": []},
        {"slug": "leg-press", "name": "Leg Press", "loading": "machine",
         "working_weight": 360, "last_performed": "2026-08-12",
         "change_30d": 20, "primary_muscle": "quads", "secondary_muscles": ["glutes"],
         "machine_settings": [{"kind": "seat", "label": "Seat", "value": "2"},
                              {"kind": "back", "label": "Back pad", "value": "4"}],
         "recent": [{"date": "2026-08-12", "top_weight": 360, "reps": [10, 10, 8],
                     "volume": 10080, "warmup_sets": 1, "average_rpe": None}]},
        {"slug": "assisted-pull-up", "name": "Assisted Pull-Up", "loading": "machine",
         "assisted": True, "working_weight": 70, "last_performed": "2026-08-18",
         "change_30d": -20, "primary_muscle": "lats", "secondary_muscles": ["biceps"],
         "best": {"weight": 70, "reps": 8, "date": "2026-08-18"},
         "recent": [{"date": "2026-08-18", "top_weight": 70, "reps": [8, 8, 7],
                     "volume": 0, "warmup_sets": 0, "average_rpe": None}]},
        {"slug": "treadmill", "name": "Treadmill", "loading": "machine",
         "modality": "cardio", "working_weight": None, "last_performed": "2026-08-20",
         "change_30d": None, "primary_muscle": "quads", "secondary_muscles": ["calves"],
         "machine_settings": [{"kind": "other", "label": "Other", "value": "belt 3"}],
         "cardio_best": {"farthest": 3.2, "longest_seconds": 2400, "fastest": 6.1},
         "recent": [{"date": "2026-08-20", "top_weight": 0, "reps": [],
                     "volume": 0, "warmup_sets": 0, "average_rpe": None,
                     "cardio": {"bouts": 1, "seconds": 1500, "distance": 2.1,
                                "average_incline": 3.0, "average_speed": 5.04}},
                    {"date": "2026-08-13", "top_weight": 0, "reps": [],
                     "volume": 0, "warmup_sets": 0, "average_rpe": None,
                     "cardio": {"bouts": 1, "seconds": 2400, "distance": 3.2,
                                "average_incline": 1.5, "average_speed": 4.8}}]},
    ],
    "plan": [],
    "passes": [
        {"name": "Blink Fitness", "location": "Union Square", "symbology": "code128",
         "member_id_masked": "•••• 4917", "state": "2 uses left",
         "expires": "2026-09-04", "expired": False, "primary": True, "has_code": True},
    ],
    "sessions": [
        {"date": "2026-08-19", "day": "Push A", "exercises": 6, "sets": 20,
         "volume": 12830, "warmup_sets": 2, "top_lifts": ["Bench Press 185"],
         "cardio_minutes": 25.0, "cardio_distance": 2.1},
        {"date": "2026-08-17", "day": "Pull A", "exercises": 5, "sets": 16,
         "volume": 15810, "warmup_sets": 0, "top_lifts": ["Deadlift 315"]},
        {"date": "2026-08-12", "day": "Legs", "exercises": 5, "sets": 17,
         "volume": 34960, "warmup_sets": 0, "top_lifts": ["Leg Press 360"]},
    ],
}


@contextlib.contextmanager
def fixture(data=None):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(FIXTURE if data is None else data, f)
        path = f.name
    old = os.environ.get("GYM_SNAPSHOT")
    os.environ["GYM_SNAPSHOT"] = path
    try:
        yield path
    finally:
        os.environ.pop("GYM_SNAPSHOT", None)
        if old is not None:
            os.environ["GYM_SNAPSHOT"] = old
        os.unlink(path)


def run(*argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = gym.main(list(argv))
    return code, out.getvalue()


class Formatting(unittest.TestCase):
    def test_weights_drop_pointless_decimals(self):
        self.assertEqual(gym.num(185.0), "185")
        self.assertEqual(gym.num(2.5), "2.5")
        self.assertEqual(gym.num(None), "—")

    def test_float_noise_is_rounded_away(self):
        # The value CoreData/JSON hands over for 176.4 - 178.2.
        self.assertEqual(gym.num(-1.799999999999983), "-1.8")
        self.assertEqual(gym.signed(-1.799999999999983), "−1.8")

    def test_no_change_is_a_dash(self):
        self.assertEqual(gym.signed(0), "—")
        self.assertEqual(gym.signed(None), "—")
        self.assertEqual(gym.signed(10), "+10")

    def test_sparkline_spans_the_block_range(self):
        line = gym.sparkline([1, 2, 3, 4, 5, 6, 7, 8])
        self.assertEqual(len(line), 8)
        self.assertEqual(line[0], "▁")
        self.assertEqual(line[-1], "█")

    def test_flat_series_does_not_divide_by_zero(self):
        self.assertEqual(gym.sparkline([5, 5, 5]), "▄▄▄")
        self.assertEqual(gym.sparkline([]), "")


class Loading(unittest.TestCase):
    def test_missing_snapshot_explains_how_to_fix_it(self):
        os.environ["GYM_SNAPSHOT"] = "/nonexistent/snapshot.json"
        try:
            with self.assertRaises(gym.NoSnapshot) as ctx:
                gym.load()
            message = str(ctx.exception)
            self.assertIn("Open Rathi Fitness on the phone", message)
            self.assertIn("iCloud Drive", message)
        finally:
            os.environ.pop("GYM_SNAPSHOT", None)

    def test_an_older_schema_is_refused_too(self):
        # A v1 snapshot counted warm-ups in volume. Reading it as v2 would report
        # a tonnage the phone never showed.
        with fixture(dict(FIXTURE, schema=1)):
            with self.assertRaises(gym.NoSnapshot) as ctx:
                gym.load()
            message = str(ctx.exception)
            # Say which side is behind. "Update whichever is older" is a puzzle.
            self.assertIn("open Rathi", message.replace("\n  ", " "))
            self.assertIn("Nothing is lost", message)

    def test_future_schema_is_refused_not_guessed_at(self):
        data = dict(FIXTURE, schema=99)
        with fixture(data):
            with self.assertRaises(gym.NoSnapshot) as ctx:
                gym.load()
            message = str(ctx.exception)
            self.assertIn("99", message)
            self.assertIn("newer than this CLI", message)

    def test_half_written_json_is_a_clear_error(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            f.write('{"schema": 1, "body_wei')
            path = f.name
        os.environ["GYM_SNAPSHOT"] = path
        try:
            with self.assertRaises(gym.NoSnapshot) as ctx:
                gym.load()
            self.assertIn("try again", str(ctx.exception))
        finally:
            os.environ.pop("GYM_SNAPSHOT", None)
            os.unlink(path)

    def test_exit_code_two_when_there_is_no_snapshot(self):
        os.environ["GYM_SNAPSHOT"] = "/nonexistent/snapshot.json"
        try:
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(gym.main(["today"]), 2)
            self.assertIn("No snapshot", err.getvalue())
        finally:
            os.environ.pop("GYM_SNAPSHOT", None)


class Commands(unittest.TestCase):
    def test_today_shows_plan_and_deviation(self):
        with fixture():
            code, out = run("today")
        self.assertEqual(code, 0)
        self.assertIn("Push A", out)
        self.assertIn("2 of 3 done", out)
        # Bench was 8,8,7,6 against a target of 8 — that is not "all four hit".
        self.assertIn("got 8, 8, 7, 6", out)
        # Cable Fly hit every rep.
        self.assertIn("all 3 hit", out)
        self.assertIn("176.4", out)

    def test_today_on_a_rest_day(self):
        data = dict(FIXTURE); data.pop("today")
        with fixture(data):
            code, out = run("today")
        self.assertEqual(code, 0)
        self.assertIn("Rest day", out)

    def test_weight_reports_trend_and_a_sparkline(self):
        with fixture():
            _, out = run("weight")
        self.assertIn("176.4", out)
        self.assertIn("−1.8", out)
        self.assertIn("−0.4/wk", out)
        self.assertTrue(any(c in out for c in gym.SPARK))

    def test_lifts_sorted_heaviest_first(self):
        with fixture():
            _, out = run("lifts")
        self.assertLess(out.index("Deadlift"), out.index("Bench Press"))
        # A lift with no 30-day comparison prints a dash, never +0.
        self.assertIn("—", out)

    def test_exercise_matches_loosely(self):
        with fixture():
            _, out = run("exercise", "bench")
        self.assertIn("Bench Press", out)
        self.assertIn("2026-08-19", out)
        self.assertIn("8, 8, 7, 6", out)

    def test_unknown_exercise_lists_what_it_knows(self):
        with fixture():
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                with self.assertRaises(SystemExit):
                    gym.main(["exercise", "bicep-curl-machine"])
            self.assertIn("Known:", err.getvalue())

    def test_sessions(self):
        with fixture():
            _, out = run("sessions")
        self.assertIn("Push A", out)
        self.assertIn("Bench Press 185", out)

    def test_json_flag_is_machine_readable(self):
        with fixture():
            _, out = run("--json", "lifts")
        parsed = json.loads(out)
        # Heaviest first — the contract the human table also relies on.
        self.assertEqual([r["name"] for r in parsed][:2], ["Leg Press", "Deadlift"])
        self.assertNotIn("Treadmill", [r["name"] for r in parsed],
                         "cardio has no working weight and must stay out of `lifts`")

    def test_status_flags_a_stale_snapshot(self):
        old = dict(FIXTURE, generated_at="2020-01-01T00:00:00Z")
        with fixture(old):
            _, out = run("status")
        self.assertIn("Stale", out)

    def test_status_is_quiet_when_fresh(self):
        import datetime as dt
        now = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with fixture(dict(FIXTURE, generated_at=now)):
            _, out = run("status")
        self.assertNotIn("Stale", out)
        self.assertIn("just now", out)


class Volume(unittest.TestCase):
    """How much you moved — the number that makes an hour of standing around
    add up to something."""

    def test_tonnage_switches_units_where_pounds_stop_being_picturable(self):
        self.assertEqual(gym.tonnage(12830), "12,830 lb")
        self.assertEqual(gym.tonnage(41200), "20.6 tons")
        self.assertEqual(gym.tonnage(0), "nothing yet")

    def test_today_reports_what_has_been_moved(self):
        with fixture():
            _, out = run("today")
        self.assertIn("Moved today: 9,420 lb", out)

    def test_today_says_nothing_about_volume_before_you_lift_anything(self):
        data = json.loads(json.dumps(FIXTURE))
        data["today"]["volume"] = 0
        with fixture(data):
            _, out = run("today")
        # A zero scoreboard is a scoreboard telling you off.
        self.assertNotIn("Moved today", out)

    def test_volume_groups_sessions_into_weeks(self):
        with fixture():
            _, out = run("volume")
        # 19 and 17 Aug are the same week (Mon 17th); the 12th is the week before.
        self.assertIn("week of 2026-08-17", out)
        self.assertIn("week of 2026-08-10", out)
        self.assertIn("2 sessions", out)

    def test_volume_totals_the_window(self):
        with fixture():
            _, out = run("volume")
        self.assertIn(gym.tonnage(12830 + 15810 + 34960), out)

    def test_volume_json_is_machine_readable(self):
        with fixture():
            _, out = run("--json", "volume")
        weeks = json.loads(out)
        self.assertEqual(weeks[-1]["volume"], 12830 + 15810)

    def test_volume_with_nothing_logged(self):
        data = json.loads(json.dumps(FIXTURE))
        data["sessions"] = []
        with fixture(data):
            _, out = run("volume")
        self.assertIn("Nothing logged yet", out)

    def test_sessions_uses_the_same_tonnage_wording(self):
        with fixture():
            _, out = run("sessions")
        self.assertIn("17.5 tons moved", out)


class SetKinds(unittest.TestCase):
    """Schema 2: RIA can see how a set was done, not just that it was."""

    def test_today_reports_rpe_and_warm_ups(self):
        with fixture():
            _, out = run("today")
        self.assertIn("RPE 8.5", out)
        self.assertIn("+1 warm-up", out)

    def test_a_warm_up_is_not_counted_as_a_working_set(self):
        with fixture():
            _, out = run("today")
        # Bench logged 5 sets, one a warm-up: four working reps are listed, and
        # the warm-up is reported separately rather than as a fifth set.
        self.assertIn("got 8, 8, 7, 6", out)
        self.assertIn("+1 warm-up", out)
        self.assertNotIn("8, 8, 7, 6, 10", out)

    def test_exercise_shows_muscles_rpe_and_warm_ups(self):
        with fixture():
            _, out = run("exercise", "bench")
        self.assertIn("chest", out)
        self.assertIn("triceps", out)
        self.assertIn("RPE 8.5", out)
        self.assertIn("(+1 warm-up)", out)

    def test_muscles_counts_primary_whole_and_secondary_half(self):
        with fixture():
            _, out = run("--json", "muscles", "--days", "3650")
        by_muscle = json.loads(out)
        # Bench: 8 working sets across two sessions in the window.
        self.assertEqual(by_muscle["chest"], 8)
        self.assertEqual(by_muscle["triceps"], 4)

    def test_muscles_says_what_to_do_when_nothing_is_mapped(self):
        data = json.loads(json.dumps(FIXTURE))
        for ex in data["exercises"]:
            ex["primary_muscle"] = "other"
            ex["secondary_muscles"] = []
        with fixture(data):
            _, out = run("muscles", "--days", "3650")
        self.assertIn("Edit the plan", out)

    def test_muscles_window_excludes_older_sessions(self):
        with fixture():
            _, out = run("--json", "muscles", "--days", "1")
        self.assertEqual(json.loads(out), {})


class Secrets(unittest.TestCase):
    """The snapshot has no codes in it; the CLI must not invent a way to want one."""

    def test_passes_shows_state_but_never_a_code(self):
        with fixture():
            _, out = run("passes")
        self.assertIn("Blink Fitness", out)
        self.assertIn("2 uses left", out)
        self.assertIn("•••• 4917", out)
        self.assertIn("Codes are never exported", out)

    def test_no_command_can_print_a_code_even_if_one_leaked_in(self):
        # Belt and braces: if a future app version ever wrote a code into the
        # snapshot, `gym` should still not be the thing that prints it.
        leaked = json.loads(json.dumps(FIXTURE))
        leaked["passes"][0]["code"] = "SECRET-CODE-1234"
        with fixture(leaked):
            for command in (["passes"], ["today"], ["lifts"], ["status"]):
                _, out = run(*command)
                self.assertNotIn("SECRET-CODE-1234", out,
                                 f"{command} printed a pass code")

    def test_raw_is_the_documented_exception(self):
        # `gym raw` is explicitly "give me the file", so it does dump whatever is
        # in it. That is why the app is the thing that must never write a code.
        leaked = json.loads(json.dumps(FIXTURE))
        leaked["passes"][0]["code"] = "SECRET-CODE-1234"
        with fixture(leaked):
            _, out = run("raw")
        self.assertIn("SECRET-CODE-1234", out)


if __name__ == "__main__":
    unittest.main()


class Cardio(unittest.TestCase):
    """A treadmill answers in minutes and miles, and never in pounds."""

    def test_today_shows_a_cardio_row_in_its_own_units(self):
        with fixture():
            _, out = run("today")
        self.assertIn("Treadmill", out)
        self.assertIn("25 min", out)
        self.assertIn("2.10 mi", out)
        # No fabricated weight column for something with no weight.
        self.assertNotIn("Treadmill              0 lb", out)

    def test_today_reports_cardio_time_alongside_tonnage(self):
        with fixture():
            _, out = run("today")
        self.assertIn("Cardio: 25 min", out)

    def test_cardio_command_totals_the_window(self):
        with fixture():
            _, out = run("cardio")
        self.assertIn("Treadmill", out)
        self.assertIn("min", out)

    def test_cardio_command_says_so_when_there_is_none(self):
        bare = dict(FIXTURE, exercises=[e for e in FIXTURE["exercises"]
                                        if e.get("modality") != "cardio"])
        with fixture(bare):
            _, out = run("cardio")
        self.assertIn("No cardio logged yet", out)

    def test_exercise_shows_cardio_history_not_a_weight(self):
        with fixture():
            _, out = run("exercise", "treadmill")
        self.assertIn("cardio", out)
        self.assertIn("furthest 3.20 mi", out)
        self.assertIn("fastest 6.1 mph", out)
        self.assertNotIn("working", out)

    def test_sessions_mention_cardio_minutes(self):
        with fixture():
            _, out = run("sessions")
        self.assertIn("25 min cardio", out)

    def test_clock_reads_like_a_person(self):
        self.assertEqual(gym.clock(1320), "22 min")
        self.assertEqual(gym.clock(5400), "1 h 30 min")
        self.assertEqual(gym.clock(3600), "1 h")
        self.assertEqual(gym.clock(0), "—")

    def test_a_metric_nobody_recorded_is_absent_rather_than_zero(self):
        # The whole reason the snapshot nulls these instead of writing 0.
        line = gym.cardio_line({"bouts": 1, "seconds": 900, "distance": 0})
        self.assertEqual(line, "15 min")
        self.assertNotIn("0%", line)
        # Not a substring check: "min" contains "mi". The claim is that no
        # distance clause was emitted at all.
        self.assertNotIn("mi\u0020", line + " ")
        self.assertEqual(line.count("·"), 0)


class Machines(unittest.TestCase):
    """Where the seat goes — the thing you otherwise rediscover by sitting down
    and finding out it is wrong."""

    def test_machines_lists_every_recorded_dial(self):
        with fixture():
            _, out = run("machines")
        self.assertIn("Leg Press", out)
        self.assertIn("seat 2", out)
        self.assertIn("back pad 4", out)

    def test_settings_appear_on_the_exercise_itself(self):
        with fixture():
            _, out = run("exercise", "leg-press")
        self.assertIn("set to", out)
        self.assertIn("seat 2", out)

    def test_machines_says_so_when_nothing_is_recorded(self):
        bare = dict(FIXTURE, exercises=[{k: v for k, v in e.items()
                                         if k != "machine_settings"}
                                        for e in FIXTURE["exercises"]])
        with fixture(bare):
            _, out = run("machines")
        self.assertIn("No machine settings recorded", out)


class SchemaGate(unittest.TestCase):
    def test_an_older_snapshot_says_the_phone_is_behind(self):
        old = dict(FIXTURE, schema=3)
        with fixture(old):
            code, _ = run("today")
        self.assertNotEqual(code, 0, "an unreadable schema must not look like success")

    def test_the_supported_schema_is_the_one_the_app_writes(self):
        # Bumping one without the other is how the CLI goes blind for a week.
        self.assertEqual(gym.SCHEMA_SUPPORTED, 4)


class Assisted(unittest.TestCase):
    """A pull-up assist counterweights you: the number going DOWN is the
    progress. Every one of these assertions is a place where saying nothing
    would have meant saying the opposite."""

    def test_the_change_column_names_the_direction(self):
        with fixture():
            _, out = run("lifts")
        self.assertIn("Assisted Pull-Up", out)
        # Not a bare "−20", which under a column headed 30d reads as losing
        # ground.
        self.assertIn("help", out)
        self.assertIn("down is up", out)

    def test_an_assisted_row_is_marked_in_the_table(self):
        with fixture():
            _, out = run("lifts")
        line = next(l for l in out.splitlines() if "Assisted Pull-Up" in l)
        self.assertIn("*", line)

    def test_the_detail_view_calls_it_help_and_calls_the_best_the_least(self):
        with fixture():
            _, out = run("exercise", "assisted-pull-up")
        self.assertIn("assisted machine", out)
        self.assertIn("help", out)
        self.assertIn("least", out)
        # "best 70 × 8" would read as a heaviest-ever personal best.
        self.assertNotIn("best    70", out)

    def test_a_plain_lift_is_untouched_by_any_of_this(self):
        with fixture():
            _, out = run("exercise", "bench-press")
        self.assertIn("working 185 lb", out)
        self.assertNotIn("help", out)

    def test_assisted_change_reads_as_help_taken_off(self):
        self.assertEqual(gym.assisted_change(-20), "−20 help")
        self.assertEqual(gym.assisted_change(10), "+10 help")
        self.assertEqual(gym.assisted_change(0), "—")
        self.assertEqual(gym.assisted_change(None), "—")
