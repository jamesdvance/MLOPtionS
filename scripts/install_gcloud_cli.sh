# Snap install isn't working - complains of no snapd.socket
# snap install google-cloud-cli --classic

sudo apt-get update

sudo apt-get install apt-transport-https ca-certificates gnupg curl

# Assumes Ubuntu >= 18.04
curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg

echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee -a /etc/apt/sources.list.d/google-cloud-sdk.list

sudo apt-get update && sudo apt-get install google-cloud-cli

# Start project and login
# gcloud init
# gcloud auth application-default login

