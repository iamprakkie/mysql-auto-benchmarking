import os
import sys

from constructs import Construct
from aws_cdk.aws_s3_assets import Asset
from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_cloud9 as cloud9,
    App, Stack, CfnOutput 
)

dirname = os.path.dirname(__file__)
mySQLinstName = "mySQLBenchmarking"

instType = os.getenv("MYSQL_INST_TYPE", "t3.nano")

class EC2InstanceStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # VPC
        vpc = ec2.Vpc(self, "VPC",
            enable_dns_hostnames = True,
            enable_dns_support = True,
            subnet_configuration=[ec2.SubnetConfiguration(name="public",subnet_type=ec2.SubnetType.PUBLIC,cidr_mask = 24)]
            )

        # VPC's subnet
        subnet_id = vpc.select_subnets(subnet_group_name="public").subnet_ids[0]

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

        #Security Group for DBT2 instance
        sg_dbt2 = ec2.SecurityGroup(
            self,
            id="sg_dbt2",
            vpc=vpc,
            allow_all_outbound=True,
            description="Security group of DBT2 instance",
            security_group_name = "sg_dbt2"
        )
        
        #Security Group for mySQL instance
        sg_mysql = ec2.SecurityGroup(
            self,
            id="sg_mysql-access",
            vpc=vpc,
            allow_all_outbound=True,
            description="Allow access to 3306 only from security group of DBT2 instance",
            security_group_name = "sg_mysql-access"
        )

        sg_mysql.add_ingress_rule(
            # peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            peer=sg_dbt2,
            connection=ec2.Port.tcp(3306),
            description="MySQL access"
        )

        #cloud9 env
        # c9env = cloud9.CfnEnvironmentEC2(self, "Cloud9Env", 
        #     instance_type=instType,
        #     subnet_id=subnet_id,
        #     connection_type="CONNECT_SSM",
        #     owner_arn="arn:aws:sts::505670647613:assumed-role/Admin/praksri-Isengard"
        # )

        # Instance
        instance = ec2.Instance(self, "Instance",
            instance_type=ec2.InstanceType(instance_type_identifier=instType),
            machine_image=amzn_linux,
            vpc=vpc,
            # vpc_subnets=ec2.SubnetSelection( subnet_group_name=subnet_id),
            security_group=sg_mysql,
            # block_devices=[
            # ec2.BlockDevice(device_name="/dev/xvda",volume=ec2.BlockDeviceVolume.ebs(30),volume_type="GP3"),
            # ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(50))
            # ],
            role = role
            )

        # ec2.Instance has no property of BlockDeviceMappings, add via lower layer cdk api:
        instance.instance.add_property_override("BlockDeviceMappings", [{
            "DeviceName": "/dev/xvda",
            "Ebs": {
                "VolumeSize": "30",
                "VolumeType": "gp3",
                "DeleteOnTermination": "true"
            }
        }, {
            "DeviceName": "/dev/sda1",
            "Ebs": {
                "VolumeSize": "50",
                "VolumeType": "io1",
                "Iops": "150",
                "DeleteOnTermination": "true"
            }
        }
        ])

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
        # CfnOutput(self, "c9Url", value=c9env.attr_arn)
        CfnOutput(self, 'vpcId', value=vpc.vpc_id, export_name='ExportedVpcId')
        CfnOutput(self, "instId", value=instance.instance_id, export_name='ExportedInstId')
        CfnOutput(self, "sgId", value=sg_mysql.security_group_id, export_name='ExportedSgId')
        
            

app = App()
EC2InstanceStack(app, mySQLinstName)
app.synth()
