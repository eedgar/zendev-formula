# zendev/init.sls
# https://github.com/zenoss/zendev/blob/develop/docs/installation.rst

# common variables

{%- set USER = pillar['zendev']['username'] -%}
{%- set user = pillar.get("users:%s" % USER, {}) -%}

{%- set HOMEDIR = user.get('home', "/home/%s" % USER) -%}

{%- set SRCDIR = '%s/src' % HOMEDIR -%}
{%- set APP_ID = pillar['zendev']['app_id'] -%}
{%- set APP_TAG = pillar['zendev']['app_tag'] -%}

# basics #####################################################################

zenoss-python-apt:
  pkg.installed:
    - name: python-apt

zenoss-repo:
  pkgrepo.managed:
    - repo: 'deb http://archive.ubuntu.com/ubuntu {{ grains.get('lsb_distrib_codename') }} main universe restricted multiverse'
    - require:
      - pkg: zenoss-python-apt

apt_update:
   cmd.wait:
      - name: /usr/bin/apt-get update
      - watch:
          - pkgrepo: zenoss-repo

# user #######################################################################

include:
  - users

user-dependencies:
  pkg.installed:
    - names:
      - git
      - tmux
      - screen

srcdir-create:
  file.directory:
    - name: {{ SRCDIR }}
    - user: {{ USER }}
    - group: {{ USER }}
    - require:
      - sls: users

git-config:
  file.managed:
    - name: {{ HOMEDIR }}/.gitconfig
    - user: {{ USER }}
    - group: {{ USER }}
    - mode: 644
    - contents_pillar: zendev:gitconfig
    - require:
      - sls: users

github-known_hosts:
  ssh_known_hosts.present:
    - name: github.com
    - user: {{ USER }}
    - fingerprint: 16:27:ac:a5:76:28:2d:36:63:1b:56:4d:eb:df:a6:48
    - require:
      - sls: users

# docker #######################################################################
docker-dependencies:
  pkg.installed:
    - names:
      - curl
      - nfs-kernel-server
      - nfs-common
      - net-tools

docker-install:
  cmd.run:
    - name: curl -sL https://get.docker.io/ubuntu/ | sudo sh
    - unless: test -x /usr/bin/docker
    - require:
      - pkg: docker-dependencies

docker_aufs:
  cmd.run:
    - name: "stop docker && apt-get remove -y lxc-docker && apt-get -y autoremove && rm -rf /var/lib/docker && apt-get update -y && apt-get install -y linux-image-extra-`uname -r` && apt-get install -y lxc-docker && start docker"
    - unless: "docker info|grep 'Storage Driver: aufs'"
    - require:
      - cmd: docker-install

docker-user:
  user.present:
    - name: {{ USER }}
    - groups:
      - docker
    - remove_groups: false
    - require:
      - cmd: docker-install

docker-defaults:
  file.managed:
    - name: /etc/default/docker
    - source: salt://zendev/docker.defaults
    - template: jinja
    - context:
      docker_opts: {{ pillar['zendev']['docker_opts'] }}

docker-service:
  service.running:
    - name: docker
    - enable: true
    - require:
      - cmd: docker-install
    - watch:
      - file: docker-defaults 

dockerhub-login:
  cmd.run:
    - name: docker login -u {{ pillar['zendev']['dockerhub']['username']}} -e {{ pillar['zendev']['dockerhub']['email'] }} -p {{ pillar['zendev']['dockerhub']['password'] }}
    - user: {{ USER }}
    - unless: test -f ~/.dockercfg
    - require:
      - user: docker-user

# go #########################################################################

go-dependencies:
  pkg.installed:
    - names:
      - mercurial
      - bzr
      - git
      - wget
      - curl
 
go-install:
  cmd.run:
    - name: curl -s https://storage.googleapis.com/golang/go1.3.3.linux-amd64.tar.gz | sudo tar -xzC /usr/local
    - unless: test -x /usr/local/go/bin/
    - require:
      - pkg: go-dependencies

go-profile:
  file.managed:
    - name: /etc/profile.d/golang.sh
    - contents: |
        export GOROOT=/usr/local/go
        export PATH=$GOROOT/bin:$PATH
        export GOPATH=/opt/go
    - require:
      - cmd: go-install

gopath:
  file.directory:
    - name: /opt/go
    - makedirs: true
    - user: {{ USER }}
    - group: {{ USER }}
    - recurse:
      - user
      - group
    - require:
      - file: go-profile

{% for subdir in ('bin', 'pkg', 'src') %}
gopath-subdir-{{ subdir }}:
  file.directory:
    - name: /opt/go/{{ subdir }}
    - user: {{ USER }}
    - group: {{ USER }}
    - require:
      - file: gopath
{% endfor %}

golint-get:
  cmd.run:
    - name: go get github.com/golang/lint/golint
    - user: {{ USER }}
    - unless: test -x /opt/go/bin/golint
    - require:
      - file: gopath

golint-link:
  file.symlink:
    - name: /usr/local/bin/golint
    - target: /opt/go/bin/golint
    - require:
      - cmd: golint-get

godef-get:
  cmd.run:
    - name: go get -v code.google.com/p/rog-go/exp/cmd/godef && go install -v code.google.com/p/rog-go/exp/cmd/godef
    - user: {{ USER }}
    - unless: test -x /opt/go/bin/godef
    - require:
      - file: gopath

godef-link:
  file.symlink:
    - name: /usr/local/bin/godef
    - target: /opt/go/bin/godef
    - require:
      - cmd: godef-get

gocode-get:
  cmd.run:
    - name: go get -u github.com/nsf/gocode
    - user: {{ USER }}
    - unless: test -x /opt/go/bin/gocode
    - require:
      - file: gopath

gocode-link:
  file.symlink:
    - name: /usr/local/bin/gocode
    - target: /opt/go/bin/gocode
    - require:
      - cmd: gocode-get

goimports-get:
  cmd.run:
    - name: go get code.google.com/p/go.tools/cmd/goimports
    - user: {{ USER }}
    - unless: test -x /opt/go/bin/goimports
    - require:
      - file: gopath

goimports-link:
  file.symlink:
    - name: /usr/local/bin/goimports
    - target: /opt/go/bin/goimports
    - require:
      - cmd: goimports-get

# python #####################################################################

pip-install:
  pkg.installed:
    - names:
      - python-dev
      - python-pip

pip-upgrade:
  cmd.run:
    - name: pip install --upgrade pip
    - unless: python -c "from pkg_resources import parse_version as pv; import pip; print pv(pip.__version__) >= pv('1.5.6')" | grep -q True
    - require:
      - pkg: pip-install

setuptools-upgrade:
  cmd.run:
    - name: pip install setuptools --no-use-wheel --upgrade
    - unless: python -c "from pkg_resources import parse_version as pv; import setuptools; print pv(setuptools.__version__) >= pv('5.7')" | grep -q True
    - require:
      - cmd: pip-upgrade

# serviced ###################################################################

serviced-dependencies:
  pkg.installed:
    - names:
      - libpam0g-dev

{% for subdir in ('blkio', 'cpuacct', 'memory') %}
cgroup-subdir-{{ subdir }}:
  file.directory:
    - name: /sys/fs/cgroup/{{ subdir }}/lxc
{% endfor %}

limits:
   file.blockreplace:
     - name: /etc/security/limits.conf
     - marker_start: "# BEGIN: salt.states.zendev"
     - marker_end: "# END: salt.states.zendev"
     - backup: '.bak'
     - append_if_not_found: True
     - content: |
           *      hard   nofile   1048576
           *      soft   nofile   1048576
           root   hard   nofile   1048576
           root   soft   nofile   1048576
     - show_changes: True



# zendev #####################################################################

zendev-dependencies:
  pkg.installed:
    - names:
      - zlib1g-dev

zendev-clone:
  git.latest:
    - name: git@github.com:zenoss/zendev
    - target: {{ SRCDIR }}/zendev
    - user: {{ USER }}
    - require:
      - file: srcdir-create
      - sls: users
      - ssh_known_hosts: github-known_hosts

zendev-egg_info:
  cmd.run:
    - name: python {{ SRCDIR }}/zendev/setup.py egg_info
    - unless: test -d {{ SRCDIR }}/zendev/zendev.egg-info
    - user: {{ USER }}
    - cwd: {{ SRCDIR }}/zendev
    - require:
      - git: zendev-clone

zendev-install:
  cmd.run:
    - name: pip install -e {{ SRCDIR }}/zendev
    - unless: which zendev
    - require:
      - cmd: zendev-egg_info
      - pkg: zendev-dependencies

zendev-bootstrap:
  file.append:
    - name: {{ HOMEDIR }}/.bashrc
    - text: source $(zendev bootstrap)
    - require:
      - cmd: zendev-install

zendev-init:
  cmd.run:
    - name: zendev init {{ APP_ID }} --tag {{ APP_TAG }}
    - cwd: {{ SRCDIR }}
    - user: {{ USER }}
    - creates: {{ SRCDIR }}/{{ APP_ID }}
    - require:
      - file: zendev-bootstrap

{% set id = 'app_' + APP_ID + '_sync' %}
{% if salt['grains.get'](id, None) == None %}
{{ APP_ID }}_zendev-sync:
  cmd.run:
    - name: zendev use {{ APP_ID }} && zendev sync
    - user: {{ USER }}

app_{{ APP_ID }}_sync:
  module.run:
    - name: grains.setval
    - key: app_{{ APP_ID }}_sync
    - val: 'complete'
{% endif %}

{% if salt['pillar.get']('zendev:buildServiced', False) %}
{% if salt['grains.get']('zendev_serviced_built', None) == None %}
build_serviced:
  cmd.script:
    - source: salt://zendev/serviced_compile
    - template: jinja
    - user: {{ USER }}
    - context:
       USER: {{ USER }}
       APP_ID: {{ APP_ID }}

zendev_serviced_built:
  module.run:
    - name: grains.setval
    - key: zendev_serviced_built
    - val: 'complete'
    - require:
       - cmd: build_serviced
{% endif %}
{% endif %}

{% if salt['pillar.get']('zendev:buildDevImg', False) %}
{% if salt['grains.get']('zendev_devimg_built', None) == None %}
build_devimg:
  cmd.script:
    - source: salt://zendev/build_devimg
    - template: jinja
    - user: {{ USER }}
    - context:
       USER: {{ USER }}
       APP_ID: {{ APP_ID }}
       DEVIMGOPTS: {{ salt['pillar.get']('zendev:DevImgOpts', "") }}

zendev_devimg_built:
  module.run:
    - name: grains.setval
    - key: zendev_devimg_built
    - val: 'complete'
    - require:
       - cmd: build_devimg
{% endif %}
{% endif %}

# Reboot 
# only if /etc/security/limits.conf changes
system.reboot:
  module.wait:
    - watch:
      - file: limits
