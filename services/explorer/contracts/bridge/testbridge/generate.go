package testbridge

//go:generate go run github.com/synapsecns/sanguine/tools/abigen generate --sol ./contract/TestSynapseBridge.sol --pkg testbridge --sol-version 0.6.12 --filename testbridge
//go:generate go run github.com/vburenin/ifacemaker -f testbridge.abigen.go -s TestSynapseBridgeFilterer  -i ITestSynapseBridgeFilterer  -p testbridge  -o filterer_generated.go -c "autogenerated file"

// ignore this line: go:generate cannot be the last line of a file