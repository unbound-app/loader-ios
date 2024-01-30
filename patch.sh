# Remove previous packages.
rm -rf packages

# Compile into .deb
gmake clean package

# Rename newly created .deb
find packages/*.deb -exec sh -c 'mv "$0" packages/Unbound.deb' {} \;