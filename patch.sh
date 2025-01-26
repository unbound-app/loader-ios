# Remove previous packages.
rm -rf packages

# Compile into .deb
gmake clean package LOGS=1

# Rename newly created .deb
find packages/*.deb -exec sh -c 'mv "$0" packages/Unbound.deb' {} \;