#!/bin/sh
# Creates basic Vagrant/Puppet setup.
# Assumes you have vagrant installed already
#
# adapted from https://gist.github.com/mmarseglia/6d4cfe2f0c7e6f582323
#
# requires one argument, name of the directory to store Vagrant config
# ./createVagrant.sh linux-server

# can't continue without git
which git || (echo "can't find git"; exit 1)

# make directory structure
mkdir -p $1/{manifests,puppet/modules/thirdparty,puppet/hiera}

# Puppetfile used for r10k
# put your required modules here
touch $1/puppet/Puppetfile

cat > $1/puppet/Puppetfile << EOF
moduledir 'modules/thirdparty'

mod 'puppetlabs/apt',
  :git => 'https://github.com/puppetlabs/puppetlabs-apt'

mod 'puppetlabs/stdlib',
  :git => 'https://github.com/puppetlabs/puppetlabs-stdlib'

mod 'puppetlabs/concat',
  :git => 'https://github.com/puppetlabs/puppetlabs-concat'
EOF

# default.pp used by Puppet to assign roles/modules to server
# add your node definitions here
touch $1/manifests/default.pp
cat > $1/manifests/default.pp << EOF
hiera_include('classes')
EOF

# add .gitignore to these directories so git will keep them in the repository
# contents of modules will be wiped out and rebuilt by r10k
touch .gitignore $1/puppet/modules
echo "thirdparty/" > $1/puppet/modules/.gitignore
# hiera may be empty but we want to keep it around
touch .gitignore $1/puppet/hiera

touch $1/puppet/hiera/common.yaml

cat > $1/puppet/hiera/common.yaml << EOF
classes:
  - common-settings
EOF
mkdir -p $1/puppet/modules/common-settings/manifests

cat > $1/puppet/modules/common-settings/manifests/init.pp << EOF
class common-settings {

  class { 'apt':
    update => { 'frequency' => 'daily' },
  }

  Class['apt'] -> Package <| |>

}
EOF

# create default hiera.yaml
cat > $1/hiera.yaml << EOF
:backends:
  - yaml
:yaml:
  :datadir: ./
:hierarchy:
  - "node/%{::fqdn}"
  - common
EOF

# create vagrant file
cat > $1/Vagrantfile << EOF
# -*- mode: ruby -*-
# vi: set ft=ruby :

# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

# list all servers to build
servers = [ 'server' ]

# set domain name for servers
domain = 'domain.local'

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

        # set box to use
        config.vm.box = "ubuntu/trusty64"

        config.vm.provider "virtualbox" do |v|
                v.customize ["modifyvm", :id, "--natdnsproxy1", "off"]
                v.customize ["modifyvm", :id, "--natdnshostresolver1", "off"]
                v.customize ["modifyvm", :id, "--memory", 512]
                v.auto_nat_dns_proxy = false
        end

        # the parent directory that contains your module directory and Puppetfile
        config.r10k.puppet_dir = 'puppet'

        # the path to your Puppetfile, within the repo
        config.r10k.puppetfile_path = 'puppet/Puppetfile'

        servers.each do |server|
                config.vm.define server do |server_config|
                        # puppet agent install bootstrap executed by Vagrant with shell provisioner
                        server_config.vm.provision "shell", path: "./puppet-bootstrap/ubuntu.sh"

                        # sync hiera config directory with guest
                        server_config.vm.synced_folder  "puppet/hiera", '/tmp/vagrant-hiera'

                        # set host name
                        server_config.vm.host_name = server + '.' + domain

                        # provision each server with puppet
                        server_config.vm.provision "puppet" do |puppet|
                                # set hiera configuration path
                                puppet.hiera_config_path = 'hiera.yaml'

                                # set module path
                                puppet.module_path = [ "puppet/modules", "puppet/modules/thirdparty" ]

                                # set working directory to our sync'd folder
                                # this will allow puppet to pick up hiera data
                                puppet.working_directory = '/tmp/vagrant-hiera'

                                # lots of output for debugging, noisy!
                                puppet.options = "--verbose"
                        end
                end
        end
end
EOF

# create a basic README
cat > $1/README << EOF
$1 Vagrant
`date`
created by `whoami`
EOF

# set up new vagrant directory for git
cd $1
cat > .gitignore << EOF
.vagrant/
EOF
git init
git add .

# add puppet bootstrap as a submodule
git submodule add https://github.com/hashicorp/puppet-bootstrap


# perform an initial commit
git commit -m "initial commit for $1"
