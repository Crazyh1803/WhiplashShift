import contextlib
import io
import os
import sys

sys.path.insert(0, os.path.expanduser("~/agent-kit/blender"))
from ak_util import report

here = os.path.join(os.getcwd(), "tools", "city_pipeline")
sys.path.insert(0, here)
import validate_industrial_market as VAL

buf = io.StringIO()
sys.argv = ["validate"]
with contextlib.redirect_stdout(buf):
    rc = VAL.main()
report(rc=rc, out=buf.getvalue().strip().splitlines())
if rc:
    raise RuntimeError("Industrial market validation failed")
