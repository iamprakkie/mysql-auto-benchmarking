import os.path
import sys

from constructs import Construct
from aws_cdk.aws_s3_assets import Asset
from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    App, Stack, CfnOutput
)

dirname = os.path.dirname(__file__)
instName = "mySQL-benchmarking"


class EC2InstanceStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # VPC
        vpc = ec2.Vpc(self, "VPC",
            enable_dns_hostnames = True,
            enable_dns_support = True,
            subnet_configuration=[ec2.SubnetConfiguration(name="public",subnet_type=ec2.SubnetType.PUBLIC,cidr_mask = 24)]
            )

        # AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux(
            generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
            )

        # Instance Role and SSM Managed Policy
        role = iam.Role(self, "InstanceSSM", assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"))

        role.add_managed_policy(iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"))

        #Security Group to allow access through interface endpoint
        sg = ec2.SecurityGroup(
            self,
            id="sg_ssm-access",
            vpc=vpc,
            allow_all_outbound=True,
            description="Allow access to 443 within VPC for SSM access",
            security_group_name = "sg_ssm-access"
        )

        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(443),
            description="HTTPS",
        )        

        # Instance
        instance = ec2.Instance(self, "Instance",
            instance_type=ec2.InstanceType("t3.nano"),
            machine_image=amzn_linux,
            vpc = vpc,
            security_group=sg,
            block_devices=[ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(30))],
            role = role
            )

        # Script in S3 as Asset
        asset = Asset(self, "Asset", path=os.path.join(dirname, "configure.sh"))
        local_path = instance.user_data.add_s3_download_command(
            bucket=asset.bucket,
            bucket_key=asset.s3_object_key
        )

        # Userdata executes script from S3
        instance.user_data.add_execute_file_command(
            file_path=local_path
            )
        asset.grant_read(instance.role)

        #Cloudformation Outputs
        CfnOutput(self, 'vpcId', value=vpc.vpc_id, export_name='ExportedVpcId')
        CfnOutput(self, "instId", value=instance.instance_id, export_name='ExportedInstId')
        CfnOutput(self, "sgId", value=sg.security_group_id, export_name='ExportedSgId')
        

app = App()
EC2InstanceStack(app, instName)
app.synth()
