#!/usr/bin/env python3

"""
Gets the URL to connect to the IDE
"""

import asyncio
import argparse
import http.client

async def retry(f, attempts=10, sleep=1.0):
    for i in range(attempts):
        try:
            return await f()
        except:
            if i == attempts - 1:
                raise
            await asyncio.sleep(sleep)

async def run(cmd, *args, timeout=None):
    proc = await asyncio.create_subprocess_exec(cmd, *args, stdout=asyncio.subprocess.PIPE)
    future = proc.communicate()
    stdout, _ = await (future if timeout is None else asyncio.wait_for(future, timeout=timeout))
    return stdout.decode("utf8")

def ping(hostname):
    conn = http.client.HTTPConnection(hostname)
    conn.request("GET", "/")
    conn.getresponse()

async def minikube():
    urls = (await run("minikube", "service", "proxy-public", "--url")).strip().split("\n")
    for i, url in enumerate(urls):
        try:
            ping(url)
            return url
        except:
            if i == len(urls) - 1:
                raise

async def local():
    ping("localhost")
    return "http://localhost"

async def cloud():
    service_info = (await run("kubectl", "get", "service", "proxy-public")).strip().split("\n")
    ip = service_info[1].split()[3]
    ping(ip)
    return "http://" + ip

async def main(variant, attempts):
    if args.variant == "minikube":
        print(await retry(minikube, attempts=attempts))
    elif args.variant == "local":
        print(await retry(local, attempts=attempts))
    elif args.variant == "cloud":
        print(await retry(cloud, attempts=attempts))
    else:
        raise Exception("unknown variant")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("variant", help="'minikube', 'local', or 'cloud'")
    parser.add_argument("--attempts", type=int, default=1, help="number of times to retry")
    args = parser.parse_args()
    asyncio.run(main(args.variant, args.attempts))
