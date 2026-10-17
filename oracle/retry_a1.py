"""Keeps asking Oracle for an Always Free Ampere A1 server until the region has room.

Free Ampere capacity in busy regions is usually exhausted, and Oracle's answer
is "try again later". This tries again later, politely, until it gets one:

  * rounds alternate between 2 OCPU / 12 GB (the whole free allowance) and
    1 OCPU / 6 GB, one request per round, since Oracle rate-limits
    LaunchInstance well below one call a minute;
  * "out of host capacity" waits about two minutes; a rate limit (429)
    backs off from 5 to 30 minutes; other server errors are retried;
  * any other error stops it, so it never loops on a real problem;
  * before every round it checks no A1 server exists yet, so it can never
    create two.

It calls LaunchInstance directly rather than applying a Resource Manager stack:
one light request per attempt instead of a Terraform job, which Resource
Manager rate-limits hard.

Usage (with the OCI SDK, e.g. the venv the CLI is installed in):

    python retry_a1.py --ssh-public-key %USERPROFILE%\\.ssh\\oracle-portfolio.key.pub

Needs an API key in ~/.oci/config. Logs to retry-a1.log beside this file.
"""

import argparse
import datetime
import pathlib
import random
import sys
import time

import oci

LOG = pathlib.Path(__file__).with_name("retry-a1.log")
SHAPE = "VM.Standard.A1.Flex"
SIZES = [(2, 12), (1, 6)]  # (OCPUs, GB), biggest first; 2/12 is the free limit


def say(text: str) -> None:
    line = f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S}  {text}"
    print(line, flush=True)
    with LOG.open("a", encoding="utf-8") as f:
        f.write(line + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--ssh-public-key", required=True, type=pathlib.Path)
    ap.add_argument("--name", default="portfolio")
    ap.add_argument("--vcn", default="portfolio-vcn")
    ap.add_argument("--boot-gb", type=int, default=50)
    ap.add_argument("--every", type=int, default=180, help="seconds between rounds")
    args = ap.parse_args()

    config = oci.config.from_file()
    tenancy = config["tenancy"]
    compute = oci.core.ComputeClient(config)
    net = oci.core.VirtualNetworkClient(config)
    identity = oci.identity.IdentityClient(config)

    ssh_key = args.ssh_public_key.read_text(encoding="utf-8").strip()
    ad = identity.list_availability_domains(tenancy).data[0].name
    vcn = next(v for v in net.list_vcns(compartment_id=tenancy).data if v.display_name == args.vcn)
    subnet = next(s for s in net.list_subnets(compartment_id=tenancy, vcn_id=vcn.id).data
                  if not s.prohibit_public_ip_on_vnic)
    images = [i for i in compute.list_images(
        compartment_id=tenancy, operating_system="Canonical Ubuntu", operating_system_version="24.04",
        shape=SHAPE, sort_by="TIMECREATED", sort_order="DESC").data
        if "Minimal" not in i.display_name]
    image = images[0]
    say(f"Looking for an A1 server in {ad}: {image.display_name}, subnet {subnet.display_name}, "
        f"sizes {', '.join(f'{c}/{m} GB' for c, m in SIZES)}, every ~{args.every}s")

    backoff = 300
    attempt = 0
    while True:
        existing = [i for i in compute.list_instances(compartment_id=tenancy).data
                    if i.shape == SHAPE and i.lifecycle_state not in ("TERMINATED", "TERMINATING")]
        if existing:
            i = existing[0]
            say(f"An A1 server already exists ({i.display_name}, {i.lifecycle_state}); nothing to do.")
            return 0

        wait = args.every + random.randint(0, 30)
        for ocpus, gb in [SIZES[attempt % len(SIZES)]]:
            attempt += 1
            try:
                inst = compute.launch_instance(oci.core.models.LaunchInstanceDetails(
                    compartment_id=tenancy,
                    availability_domain=ad,
                    display_name=args.name,
                    shape=SHAPE,
                    shape_config=oci.core.models.LaunchInstanceShapeConfigDetails(
                        ocpus=float(ocpus), memory_in_gbs=float(gb)),
                    source_details=oci.core.models.InstanceSourceViaImageDetails(
                        image_id=image.id, boot_volume_size_in_gbs=args.boot_gb),
                    create_vnic_details=oci.core.models.CreateVnicDetails(
                        subnet_id=subnet.id, assign_public_ip=True),
                    metadata={"ssh_authorized_keys": ssh_key},
                    is_pv_encryption_in_transit_enabled=True,
                )).data
            except oci.exceptions.ServiceError as e:
                if e.status == 500 and "capacity" in (e.message or "").lower():
                    say(f"Try {attempt}: no room for {ocpus}/{gb} GB.")
                    continue
                if e.status == 429:
                    say(f"Try {attempt}: rate limited by Oracle; waiting {backoff // 60} minutes.")
                    wait = backoff
                    backoff = min(backoff * 2, 1800)
                    break
                if e.status >= 500:
                    say(f"Try {attempt}: Oracle error {e.status} {e.code}; will retry.")
                    break
                say(f"Try {attempt}: stopping on {e.status} {e.code}: {e.message}")
                return 1
            else:
                say(f"SUCCESS: {inst.display_name} ({ocpus} OCPU / {gb} GB) is {inst.lifecycle_state}. "
                    "It shows its public IP under Compute > Instances in a minute or two.")
                if sys.platform == "win32":
                    import winsound
                    for _ in range(3):
                        winsound.Beep(880, 300)
                return 0
        else:
            backoff = 300  # a full round without a rate limit resets the back-off
        time.sleep(wait)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        say("Stopped by hand.")
