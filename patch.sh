rm -rf packages/*
make clean package
find packages/*.deb -exec sh -c 'mv "$0" packages/Unbound.deb' {} \;