#!/usr/bin/env bash

# **fixup_stuff.sh**

# fixup_stuff.sh
#
# All distro and package specific hacks go in here
# - prettytable 0.7.2 permissions are 600 in the package and
#   pip 1.4 doesn't fix it (1.3 did)
# - httplib2 0.8 permissions are 600 in the package and
#   pip 1.4 doesn't fix it (1.3 did)
# - RHEL6:
#   - set selinux not enforcing
#   - (re)start messagebus daemon
#   - remove distro packages python-crypto and python-lxml
#   - pre-install hgtools to work around a bug in RHEL6 distribute
#   - install nose 1.1 from EPEL


# Keep track of the current directory
TOOLS_DIR=$(cd $(dirname "$0") && pwd)
TOP_DIR=$(cd $TOOLS_DIR/..; pwd)

# Change dir to top of devstack
cd $TOP_DIR

# Import common functions
source $TOP_DIR/functions

FILES=$TOP_DIR/files


# Python Packages
# ---------------

# Pre-install affected packages so we can fix the permissions
pip_install prettytable
pip_install httplib2

SITE_DIRS=$(python -c "import site; import os; print os.linesep.join(site.getsitepackages())")
for dir in $SITE_DIRS; do

    # Fix prettytable 0.7.2 permissions
    if [[ -r $dir/prettytable.py ]]; then
        sudo chmod +r $dir/prettytable-0.7.2*/*
    fi

    # Fix httplib2 0.8 permissions
    httplib_dir=httplib2-0.8.egg-info
    if [[ -d $dir/$httplib_dir ]]; then
        sudo chmod +r $dir/$httplib_dir/*
    fi

done


# RHEL6
# -----

if [[ $DISTRO =~ (rhel6) ]]; then

    # Disable selinux to avoid configuring to allow Apache access
    # to Horizon files or run nodejs (LP#1175444)
    # FIXME(dtroyer): see if this can be skipped without node or if Horizon is not enabled
    if selinuxenabled; then
        sudo setenforce 0
    fi

    # If the ``dbus`` package was installed by DevStack dependencies the
    # uuid may not be generated because the service was never started (PR#598200),
    # causing Nova to stop later on complaining that ``/var/lib/dbus/machine-id``
    # does not exist.
    sudo service messagebus restart

    # The following workarounds break xenserver
    if [ "$VIRT_DRIVER" != 'xenserver' ]; then
        # An old version of ``python-crypto`` (2.0.1) may be installed on a
        # fresh system via Anaconda and the dependency chain
        # ``cas`` -> ``python-paramiko`` -> ``python-crypto``.
        # ``pip uninstall pycrypto`` will remove the packaged ``.egg-info``
        #  file but leave most of the actual library files behind in
        # ``/usr/lib64/python2.6/Crypto``. Later ``pip install pycrypto``
        # will install over the packaged files resulting
        # in a useless mess of old, rpm-packaged files and pip-installed files.
        # Remove the package so that ``pip install python-crypto`` installs
        # cleanly.
        # Note: other RPM packages may require ``python-crypto`` as well.
        # For example, RHEL6 does not install ``python-paramiko packages``.
        uninstall_package python-crypto

        # A similar situation occurs with ``python-lxml``, which is required by
        # ``ipa-client``, an auditing package we don't care about.  The
        # build-dependencies needed for ``pip install lxml`` (``gcc``,
        # ``libxml2-dev`` and ``libxslt-dev``) are present in
        # ``files/rpms/general``.
        uninstall_package python-lxml
    fi

    # ``setup.py`` contains a ``setup_requires`` package that is supposed
    # to be transient.  However, RHEL6 distribute has a bug where
    # ``setup_requires`` registers entry points that are not cleaned
    # out properly after the setup-phase resulting in installation failures
    # (bz#924038).  Pre-install the problem package so the ``setup_requires``
    # dependency is satisfied and it will not be installed transiently.
    # Note we do this before the track-depends in ``stack.sh``.
    pip_install hgtools


    # RHEL6's version of ``python-nose`` is incompatible with Tempest.
    # Install nose 1.1 (Tempest-compatible) from EPEL
    install_package python-nose1.1
    # Add a symlink for the new nosetests to allow tox for Tempest to
    # work unmolested.
    sudo ln -sf /usr/bin/nosetests1.1 /usr/local/bin/nosetests

fi
