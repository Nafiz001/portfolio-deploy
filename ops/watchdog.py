"""Starts any Oracle instance that has been stopped, such as by idle reclaim.

Run by .github/workflows/watchdog.yml. Exits 1 when it had to start something
or could not, so the failed run makes GitHub email the owner. Reads the API key
from OCI_* variables, or from ~/.oci/config when they are not set.
"""
import os
import sys

import oci


def config():
    if not os.environ.get("OCI_KEY"):
        return oci.config.from_file()
    return {
        "user": os.environ["OCI_USER"],
        "tenancy": os.environ["OCI_TENANCY"],
        "fingerprint": os.environ["OCI_FINGERPRINT"],
        "region": os.environ["OCI_REGION"],
        "key_content": os.environ["OCI_KEY"],
    }


def main():
    dry_run = "--dry-run" in sys.argv
    cfg = config()
    compute = oci.core.ComputeClient(cfg)
    instances = oci.pagination.list_call_get_all_results(compute.list_instances, cfg["tenancy"]).data
    if not instances:
        print("No instances found: check the key's permissions.")
        return 1

    alarm = False
    for i in instances:
        print(f"{i.display_name}: {i.lifecycle_state}")
        if i.lifecycle_state != "STOPPED":
            continue
        alarm = True
        if dry_run:
            print(f"  would start {i.display_name}")
            continue
        try:
            compute.instance_action(i.id, "START")
            print(f"  STARTED {i.display_name}: it had been stopped")
        except oci.exceptions.ServiceError as e:
            # An A1 can hit "Out of host capacity"; the next run tries again.
            print(f"  COULD NOT START {i.display_name}: {e.code}: {e.message}")
    return 1 if alarm else 0


if __name__ == "__main__":
    sys.exit(main())
