#
# Cookbook Name: hadoop
# Recipe: default.rb
#
# Copyright (c) 2011 Dell Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Author: Paul Webster
#

require File.join(File.dirname(__FILE__), '../libraries/common')

#######################################################################
# Begin recipe transactions
#######################################################################
debug = node[:hadoop][:debug]
Chef::Log.info("BEGIN hadoop:default") if debug

# Local variables
process_owner = node[:hadoop][:cluster][:process_file_system_owner]
mapred_owner = node[:hadoop][:cluster][:mapred_file_system_owner]
hdfs_owner = node[:hadoop][:cluster][:hdfs_file_system_owner]
hadoop_group = node[:hadoop][:cluster][:global_file_system_group]

# Configuration filter for our crowbar environment
env_filter = " AND environment:#{node[:hadoop][:config][:environment]}"

# Install the Oracle/SUN JAVA package (Hadoop requires the JDK).
package "jdk" do
  action :install
end

# Make sure that ip6tables is off.
bash "Make sure ip6tables is off" do
  code "/sbin/chkconfig ip6tables off"
  only_if "/sbin/chkconfig --list ip6tables | grep -q on"
end

# Make sure that ip6tables service is off
bash "Make sure ip6tables service is off" do
  code "service ip6tables stop"
  not_if "service ip6tables status | grep -q stopped"
end

# Install the hadoop base package.
package "hadoop-0.20" do
  action :install
end

# Find the master name nodes (there should only be one). 
master_name_nodes = Array.new
master_name_node_objects = Array.new
search(:node, "roles:hadoop-masternamenode#{env_filter}") do |nmas|
  if !nmas[:fqdn].nil? && !nmas[:fqdn].empty?
    Chef::Log.info("MASTER [#{nmas[:fqdn]}") if debug
    master_name_nodes << nmas[:fqdn]
    master_name_node_objects << nmas
  end
end
node[:hadoop][:cluster][:master_name_nodes] = master_name_nodes

# Check for errors
if master_name_nodes.length == 0
  Chef::Log.info("WARNING - Cannot find Hadoop master name node")
elsif master_name_nodes.length > 1
  Chef::Log.info("WARNING - More than one master name node found, using #{master_name_nodes[0]}")
end

# Find the secondary name nodes (there should only be one). 
secondary_name_nodes = Array.new
secondary_name_node_objects = Array.new
search(:node, "roles:hadoop-secondarynamenode#{env_filter}") do |nsec|
  if !nsec[:fqdn].nil? && !nsec[:fqdn].empty?
    Chef::Log.info("SECONDARY [#{nsec[:fqdn]}") if debug
    secondary_name_nodes << nsec[:fqdn]
    secondary_name_node_objects << nsec
  end
end
node[:hadoop][:cluster][:secondary_name_nodes] = secondary_name_nodes

# Check for errors
if secondary_name_nodes.length == 0
  Chef::Log.info("WARNING - Cannot find Hadoop secondary name node")
elsif secondary_name_nodes.length > 1
  Chef::Log.info("WARNING - More than one secondary name node found, using #{secondary_name_nodes[0]}")
end

# Find the edge nodes. 
edge_nodes = Array.new
search(:node, "roles:hadoop-edgenode#{env_filter}") do |nedge|
  if !nedge[:fqdn].nil? && !nedge[:fqdn].empty?
    Chef::Log.info("EDGE [#{nedge[:fqdn]}") if debug
    edge_nodes << nedge[:fqdn] 
  end
end
node[:hadoop][:cluster][:edge_nodes] = edge_nodes

# Find the slave nodes. 
slave_nodes = Array.new
search(:node, "roles:hadoop-slavenode#{env_filter}") do |nslave|
  if !nslave[:fqdn].nil? && !nslave[:fqdn].empty?
    Chef::Log.info("SLAVE [#{nslave[:fqdn]}") if debug
    slave_nodes << nslave[:fqdn] 
  end
end
node[:hadoop][:cluster][:slave_nodes] = slave_nodes

if debug
  Chef::Log.info("MASTER_NAME_NODES    {" + node[:hadoop][:cluster][:master_name_nodes] .join(",") + "}")
  Chef::Log.info("SECONDARY_NAME_NODES {" + node[:hadoop][:cluster][:secondary_name_nodes].join(",") + "}")
  Chef::Log.info("EDGE_NODES           {" + node[:hadoop][:cluster][:edge_nodes].join(",") + "}")
  Chef::Log.info("SLAVE_NODES          {" + node[:hadoop][:cluster][:slave_nodes].join(",") + "}")
end

# Set the authoritative name node URI (i.e. hdfs://admin.example.com:8020).
node[:hadoop][:core][:fs_default_name] = "file:///"
if master_name_nodes.length > 0
  fqdn = master_name_nodes[0]
  port = node[:hadoop][:hdfs][:dfs_access_port]
  fs_default_name = "hdfs://#{fqdn}:#{port}"
  Chef::Log.info("fs_default_name #{fs_default_name}") if debug
  node[:hadoop][:core][:fs_default_name] = fs_default_name
end

# Map/Reduce setup
# mapred.job.tracker needs to be set to the IP of the Master Node running job tracker
# mapred.job.tracker.http.address needs to also be set to the above IP
master_node_ip = "0.0.0.0"
if !master_name_node_objects.nil? && master_name_node_objects.length > 0
  master_node_ip = BarclampLibrary::Barclamp::Inventory.get_network_by_type(master_name_node_objects[0],"admin").address
end
Chef::Log.info("master_node_ip #{master_node_ip}") if debug

# The host and port that the MapReduce job tracker runs at. If "local",
# then jobs are run in-process as a single map and reduce task.
node[:hadoop][:mapred][:mapred_job_tracker] = "#{master_node_ip}:50030"

# The job tracker http server address and port the server will listen on.
# If the port is 0 then the server will start on a free port "0.0.0.0:50030".
node[:hadoop][:mapred][:mapred_job_tracker_http_address] = "#{master_node_ip}:50031"

secondary_node_ip = "0.0.0.0"
if !secondary_name_node_objects.nil? && secondary_name_node_objects.length > 0
  secondary_node_ip = BarclampLibrary::Barclamp::Inventory.get_network_by_type(secondary_name_node_objects[0],"admin").address
end
Chef::Log.info("secondary_node_ip #{secondary_node_ip}") if debug

# The secondary namenode http server address and port. If the port is 0
# then the server will start on a free port.
node[:hadoop][:hdfs][:dfs_secondary_http_address] = "#{secondary_node_ip}:50090"
node.save

# Create hadoop_log_dir and set ownership/permissions (/var/log/hadoop). 
hadoop_log_dir = node[:hadoop][:env][:hadoop_log_dir]
directory hadoop_log_dir do
  owner process_owner
  group hadoop_group
  mode "0775"
  action :create
end

# Create hadoop_tmp_dir and ownership/permissions (/tmp/hadoop-crowbar).
hadoop_tmp_dir = node[:hadoop][:core][:hadoop_tmp_dir]
directory hadoop_tmp_dir do
  owner process_owner
  group hadoop_group
  mode "0775"
  action :create
end

# Create fs_s3_buffer_dir and ownership/permissions (/tmp/hadoop-crowbar/s3).
fs_s3_buffer_dir = node[:hadoop][:core][:fs_s3_buffer_dir]
directory fs_s3_buffer_dir do
  owner hdfs_owner
  group hadoop_group
  mode "0775"
  recursive true
  action :create
end

# Create mapred_system_dir and set ownership/permissions (/mapred/system).
# Directory recursive does not set the parent directory owner, group
# and permissions correctly.
mapred_system_dir = node[:hadoop][:mapred][:mapred_system_dir]
make_dir_path(mapred_system_dir, mapred_owner, hadoop_group, "0775")
# directory mapred_system_dir do
#  owner mapred_owner
#  group hadoop_group
#  mode "0775"
#  recursive true
#  action :create
# end

# Create mapred_local_dir and set ownership/permissions (/var/lib/hadoop-0.20/cache/mapred/mapred/local).
mapred_local_dir = node[:hadoop][:mapred][:mapred_local_dir]
mapred_local_dir.each do |path|
  directory path do
    owner mapred_owner
    group hadoop_group
    mode "0755"
    recursive true
    action :create
  end
end

# Create dfs_name_dir and set ownership/permissions (/mnt/hdfs/hdfs01/meta1).
dfs_name_dir = node[:hadoop][:hdfs][:dfs_name_dir]
dfs_name_dir.each do |path|
  directory path do
    owner hdfs_owner
    group hadoop_group
    mode "0755"
    recursive true
    action :create
  end
end

#######################################################################
# Process common hadoop related configuration templates.
#######################################################################

# Configure /etc/security/limits.conf.  
# mapred      -    nofile     32768
# hdfs        -    nofile     32768
# hbase       -    nofile     32768
template "/etc/security/limits.conf" do
  owner "root"
  group "root"
  mode "0644"
  source "limits.conf.erb"
end

# Configure the master nodes.  
template "/etc/hadoop/conf/masters" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "masters.erb"
end

# Configure the slave nodes.  
template "/etc/hadoop/conf/slaves" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "slaves.erb"
end

# Configure the hadoop core component.
template "/etc/hadoop/conf/core-site.xml" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "core-site.xml.erb"
end

# Configure the HDFS component.
template "/etc/hadoop/conf/hdfs-site.xml" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "hdfs-site.xml.erb"
end

# Configure the MAP/Reduce component.
template "/etc/hadoop/conf/mapred-site.xml" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "mapred-site.xml.erb"
end

# Configure the Hadoop ENV component.
template "/etc/hadoop/conf/hadoop-env.sh" do
  owner process_owner
  group hadoop_group
  mode "0755"
  source "hadoop-env.sh.erb"
end

# Configure hadoop-metrics.properties.
template "/etc/hadoop/conf/hadoop-metrics.properties" do
  owner process_owner
  group hadoop_group
  mode "0644"
  source "hadoop-metrics.properties.erb"
end

#######################################################################
# End of recipe transactions
#######################################################################
Chef::Log.info("END hadoop:default") if debug
