# Builds and runs all pulp.json files in tests/ folder in order.
# Feel free to add some tests of your own to that folder.

PLAYDATE_SDK_PATH="${PLAYDATE_SDK_PATH/\~/$HOME}"

echo "$PLAYDATE_SDK_PATH"

for f in ./tests/*.json*; do
    echo "Processing $f"
    sleep 0.1
    python3 ./pulplua.py "$f" out-test
    
    if [ "$?" -ne 0 ]; then
        echo "ERROR: transpiling. ($f)"
        exit 1
    fi
    
    sleep 0.1
    pdc out-test Test.pdx -sdkpath "$PLAYDATE_SDK_PATH"
    if [ "$?" -ne 0 ]; then
        echo "ERROR: pdc. ($f)"
        exit 2
    fi
    
    if [ ! -d Test.pdx ]; then
        echo "ERROR: pdc did not create .pdx. ($f)"
        exit 4
    fi
    
    sleep 0.1
    PlaydateSimulator Test.pdx
    if [ "$?" -ne 0 ]; then
        echo "ERROR: simulator. ($f)"
        exit 3
    fi
done