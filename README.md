curl https://raw.githubusercontent.com/onlyHydra/rickroll/refs/heads/main/rickroll.sh --output rickroll.sh && chmod 777 rickroll.sh && ./rickroll.sh


(permanent alias)
echo "alias rickroll='./rickroll.sh'" >> ~/.bashrc
(use timeout )

timeout 3000 docker run --rm -it ghcr.io/gabe565/ascii-movie play


