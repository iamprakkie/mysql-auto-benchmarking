import os
import sys

from constructs import Construct
from aws_cdk.aws_s3_assets import Asset
from aws_cdk import (
    aws_ec2 as ec2,
    aws_iam as iam,
    App, Stack, CfnOutput 
)

dirname = os.path.dirname(__file__)
mySQLInstName = "mySQLBenchmarking"

instType = os.getenv("MYSQL_INST_TYPE", "t3.nano")
volSize=int(os.getenv("MYSQL_VOL_SIZE", 50))
volType=ec2.EbsDeviceVolumeType.IO1
volIOPS=int(os.getenv("MYSQL_VOL_IOPS", 150))

class EC2InstanceStack(Stack):

    def __init__(self, scope: Construct, id: str, **kwargs) -> None:
        super().__init__(scope, id, **kwargs)

        # VPC
        vpc = ec2.Vpc(self, "VPC",
            enable_dns_hostnames = True,
            enable_dns_support = True,
            subnet_configuration=[ec2.SubnetConfiguration(name="public",subnet_type=ec2.SubnetType.PUBLIC,cidr_mask = 24)]
            )
        
        # create AZ lookup for subnet IDs
        publicSubnets = vpc.select_subnets(subnet_group_name="public")
        az_lookup = {}
        for publicSubnet in publicSubnets.subnets:
            az_lookup[publicSubnet.subnet_id] = publicSubnet.availability_zone

        #get subnet ID           
        publicSubnetId = vpc.select_subnets(subnet_group_name="public").subnet_ids[0]

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
            id="dbt2-sg",
            vpc=vpc,
            allow_all_outbound=True,
            description="Security group of DBT2 instance",
            security_group_name = "dbt2-sg"
        )
        
        #Security Group for mySQL instance
        sg_mysql = ec2.SecurityGroup(
            self,
            id="mysql-access-sg",
            vpc=vpc,
            allow_all_outbound=True,
            description="Allow access to 3306 only from security group of DBT2 instance",
            security_group_name = "mysql-access-sg"
        )

        sg_mysql.add_ingress_rule(
            # peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
            peer=sg_dbt2,
            connection=ec2.Port.tcp(3306),
            description="MySQL access"
        )

        # DBT2 Instance
        dbt2Instance = ec2.Instance(self, "DBT2Instance",
            instance_type=ec2.InstanceType(instance_type_identifier=instType),
            machine_image=amzn_linux,
            vpc=vpc,
            vpc_subnets=ec2.SubnetSelection(subnets=[ec2.Subnet.from_subnet_attributes(self,"publicSubnet",subnet_id=publicSubnetId,availability_zone=az_lookup[publicSubnetId])]),
            security_group=sg_dbt2,
            block_devices=[
                ec2.BlockDevice(device_name="/dev/xvda",volume=ec2.BlockDeviceVolume.ebs(30,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3)),
                ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(100,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3))
            ],
            role = role
            )
        
        # Script in S3 as Asset
        asset = Asset(self, "dbt2Asset", path=os.path.join(dirname, "dbt2-instance-user-data.sh"))
        local_path = dbt2Instance.user_data.add_s3_download_command(
            bucket=asset.bucket,
            bucket_key=asset.s3_object_key
        )

        # Userdata executes script from S3
        dbt2Instance.user_data.add_execute_file_command(
            file_path=local_path
            )
        asset.grant_read(dbt2Instance.role)        

        # mySQL Instance
        mySQLInstance = ec2.Instance(self, "MySQLInstance",
            instance_type=ec2.InstanceType(instance_type_identifier=instType),
            machine_image=amzn_linux,
            vpc=vpc,
            # vpc_subnets=ec2.SubnetSelection( subnet_group_name=subnet_id),
            security_group=sg_mysql,
            block_devices=[
                ec2.BlockDevice(device_name="/dev/xvda",volume=ec2.BlockDeviceVolume.ebs(30,delete_on_termination=True,volume_type=ec2.EbsDeviceVolumeType.GP3)),
                ec2.BlockDevice(device_name="/dev/sda1",volume=ec2.BlockDeviceVolume.ebs(volSize,delete_on_termination=True,iops=volIOPS,volume_type=volType))
            ],
            role = role
            )

        # ec2.Instance has no property of BlockDeviceMappings, add via lower layer cdk api:
        # mySQLInstance.instance.add_property_override("BlockDeviceMappings", [{
        #     "DeviceName": "/dev/xvda",
        #     "Ebs": {
        #         "VolumeSize": "30",
        #         "VolumeType": "gp3",
        #         "DeleteOnTermination": "true"
        #     }
        # }, {
        #     "DeviceName": "/dev/sda1",
        #     "Ebs": {
        #         "VolumeSize": "50",
        #         "VolumeType": "io1",
        #         "Iops": "150",
        #         "DeleteOnTermination": "true"
        #     }
        # }
        # ])

        # Script in S3 as Asset
        asset = Asset(self, "mySQLAsset", path=os.path.join(dirname, "mysql-instance-user-data.sh"))
        local_path = mySQLInstance.user_data.add_s3_download_command(
            bucket=asset.bucket,
            bucket_key=asset.s3_object_key
        )

        # Userdata executes script from S3
        mySQLInstance.user_data.add_execute_file_command(
            file_path=local_path
            )
        asset.grant_read(mySQLInstance.role)

        #Cloudformation Outputs
        CfnOutput(self, 'vpcId', value=vpc.vpc_id, export_name='ExportedVpcId')
        CfnOutput(self, "dbt2InstId", value=dbt2Instance.instance_id, export_name='ExportedDBT2InstId')
        CfnOutput(self, "mySQLInstId", value=mySQLInstance.instance_id, export_name='ExportedMySQLInstId')
        #CfnOutput(self, "sgId", value=sg_mysql.security_group_id, export_name='ExportedSgId')
        
app = App()
EC2InstanceStack(app, mySQLInstName)
app.synth()
