# Path to wherever you keep your source. I like ~/src.
SRCDIR=~/src

# If SRCDIR does not exist, create it
mkdir -p ${SRCDIR}

# Switch to your source directory
cd ${SRCDIR}

# Clone zendev
git clone git@github.com:zenoss/zendev

# Enter the zendev directory
cd ${SRCDIR}/zendev

# Generate egg_info as current user to prevent permission problems
# down the road
python ${SRCDIR}/zendev/setup.py egg_info

# Install zendev in place. This means that changes to zendev source will
# take effect without reinstalling the package.
sudo pip install -e ${SRCDIR}/zendev

# Bootstrap zendev so it can modify the shell environment (i.e., change
# directories, set environment variables)
echo 'source $(zendev bootstrap)' >> ~/.bashrc

# Source it in the current shell
source $(zendev bootstrap)

# Get back to source directory
cd ${SRCDIR}

# Create the environment for building core devimg
zendev init europa --tag europa-release

# Start using the environment
zendev use europa

# This may be needed if the above zendev init failed to clone some repos
zendev sync

# Optional: add enterprise zenpacks for building resmgr devimg
zendev add ~/src/europa/build/manifests/zenpacks.commercial.json

touch ~/.zendev_bootstrapped
