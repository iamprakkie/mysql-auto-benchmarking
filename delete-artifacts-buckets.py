#!/usr/bin/env python
import boto3

s3 = boto3.resource('s3')

for bucket in s3.buckets.all():
    if bucket.name.startswith('autobench-') and bucket.name.endswith('-artifacts'):
        bucket.object_versions.all().delete()
        bucket.delete()
        print("Deleted bucket: " + bucket.name)
