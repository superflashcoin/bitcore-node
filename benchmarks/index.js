'use strict';

var benchmark = require('benchmark');
var bitcoin = require('bitcoin');
var async = require('async');
var maxTime = 20;

console.log('Bitcoin Service native interface vs. Bitcoin JSON RPC interface');
console.log('----------------------------------------------------------------------');

// To run the benchmarks a fully synced Bitcore Core directory is needed. The RPC comands
// can be modified to match the settings in bitcoin.conf.

var fixtureData = {
  blockHashes: [
    '7e6d6c92d3b78fcb7b08a20c3bdd682cf61d3bee36bd68ce77b042185337bafd',
    '2a132a88fad943693d941322ff2af59891ecf7bc4c484170bb85f7bcb5c5cd4c',
    '7af41be2ef8e55c76ee08c9c0c2b4c23e7fee1f7dbb009d65251fff8e599ce99',
    'ed350bc0d9951711a8b989c09a5034d21adb0d6c74b43bc316ea232a18c8a6e9'
  ],
  txHashes: [
    '2ab294430bc6890c874caeac0e4786372458ad9c586260ab4d659c297a822b33',
    '2859aaf48cf648f88d3e7c139e9285760a496700d1e583b81a320eeef4e7cfe7',
    '497e3598bf3b68d3ad5fad2ef47ab92d377007f2a456401b41df3dd01249751f',
    '7d14473ce2ba570b697e05c76cc2bbac5d951617f6d612ac64be88a7f3c2ff5a',
  ]
};

var bitcoind = require('../').services.Bitcoin({
  node: {
    datadir: process.env.HOME + '/.bitcore/data',
    network: {
      name: 'livenet'
    }
  }
});

bitcoind.on('error', function(err) {
  console.error(err.message);
});

bitcoind.start(function(err) {
  if (err) {
    throw err;
  }
  console.log('process.env.HOME: ', process.env.HOME);
  console.log('Bitcoin Core started');
});

bitcoind.on('ready', function() {

  console.log('Bitcoin Core ready');

  var client = new bitcoin.Client({
    host: 'localhost',
    port: 9332,
    user: 'goldbitrpc',
    pass: 'HPZhKMuHchozzwXDe4sgSoCAeCDZmreEvmpxVuXProTe'
  });

  async.series([
    function(next) {

      var c = 0;
      var hashesLength = fixtureData.blockHashes.length;
      var txLength = fixtureData.txHashes.length;

      function bitcoindGetBlockNative(deffered) {
        if (c >= hashesLength) {
          c = 0;
        }
        var hash = fixtureData.blockHashes[c];
        bitcoind.getBlock(hash, function(err, block) {
          if (err) {
            throw err;
          }
          deffered.resolve();
        });
        c++;
      }

      function bitcoindGetBlockJsonRpc(deffered) {
        if (c >= hashesLength) {
          c = 0;
        }
        var hash = fixtureData.blockHashes[c];
        client.getBlock(hash, false, function(err, block) {
          if (err) {
            throw err;
          }
          deffered.resolve();
        });
        c++;
      }

      function bitcoinGetTransactionNative(deffered) {
        if (c >= txLength) {
          c = 0;
        }
        var hash = fixtureData.txHashes[c];
        bitcoind.getTransaction(hash, true, function(err, tx) {
          if (err) {
            throw err;
          }
          deffered.resolve();
        });
        c++;
      }

      function bitcoinGetTransactionJsonRpc(deffered) {
        if (c >= txLength) {
          c = 0;
        }
        var hash = fixtureData.txHashes[c];
        client.getRawTransaction(hash, function(err, tx) {
          if (err) {
            throw err;
          }
          deffered.resolve();
        });
        c++;
      }

      var suite = new benchmark.Suite();

      suite.add('bitcoind getblock (native)', bitcoindGetBlockNative, {
        defer: true,
        maxTime: maxTime
      });

      suite.add('bitcoind getblock (json rpc)', bitcoindGetBlockJsonRpc, {
        defer: true,
        maxTime: maxTime
      });

      suite.add('bitcoind gettransaction (native)', bitcoinGetTransactionNative, {
        defer: true,
        maxTime: maxTime
      });

      suite.add('bitcoind gettransaction (json rpc)', bitcoinGetTransactionJsonRpc, {
        defer: true,
        maxTime: maxTime
      });

      suite
          .on('cycle', function(event) {
            console.log(String(event.target));
          })
          .on('complete', function() {
            console.log('Fastest is ' + this.filter('fastest').pluck('name'));
            console.log('----------------------------------------------------------------------');
            next();
          })
          .run();
    }
  ], function(err) {
    if (err) {
      throw err;
    }
    console.log('Finished');
    bitcoind.stop(function(err) {
      if (err) {
        console.error('Fail to stop services: ' + err);
        process.exit(1);
      }
      process.exit(0);
    });
  });
});
