set -euo pipefail

mkdir -p ~/.local/{bin,src}

# Install the Test::Output Perl package
cd ~/.local/src/
wget https://github.com/briandfoy/test-output/archive/refs/tags/release-1.033.zip
# or
unzip release-1.033.zip


cd test-output-release-1.033
cpan Test::Output

# Install the stow itself
cd ~/.local/src/
wget http://ftp.gnu.org/gnu/stow/stow-latest.tar.gz
tar -xvf stow-latest.tar.gz
rm stow-latest.tar.gz
cd stow-*
./configure --prefix="$HOME"/.local/bin/stow-bin
make
make install
