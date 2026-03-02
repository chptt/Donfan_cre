'use client';
import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { formatEther } from '@/lib/contract';

export default function DonationPanel({ tokenId, contract, signer, onSuccess }) {
  const [requiredETH, setRequiredETH] = useState('0');
  const [requiredUSD, setRequiredUSD] = useState('0');
  const [status, setStatus] = useState('idle');
  const [txHash, setTxHash] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const fetchRequiredAmount = async () => {
      if (!contract) return;
      
      try {
        setLoading(true);
        // Get required ETH from contract
        const requiredWei = await contract.viewRequiredETH();
        setRequiredETH(formatEther(requiredWei));
        
        // Get USD amount (in cents)
        const usdCents = await contract.donationAmountUSD();
        setRequiredUSD((Number(usdCents) / 100).toFixed(2));
        
        setLoading(false);
      } catch (error) {
        console.error('Error fetching required amount:', error);
        setLoading(false);
      }
    };

    fetchRequiredAmount();
    // Refresh every 30 seconds to get updated ETH price
    const interval = setInterval(fetchRequiredAmount, 30000);
    
    return () => clearInterval(interval);
  }, [contract]);

  const handleDonate = async () => {
    if (!signer) {
      alert('Please connect your wallet');
      return;
    }

    try {
      setStatus('signing');
      const contractWithSigner = contract.connect(signer);
      
      // Get the latest required ETH amount
      const requiredWei = await contract.viewRequiredETH();
      
      const tx = await contractWithSigner.donate(tokenId, {
        value: requiredWei
      });

      setStatus('pending');
      setTxHash(tx.hash);

      await tx.wait();
      setStatus('confirmed');
      setShowModal(true);
      onSuccess?.();

      setTimeout(() => {
        setStatus('idle');
        setShowModal(false);
      }, 5000);
    } catch (error) {
      console.error('Donation error:', error);
      setStatus('failed');
      alert(error.reason || error.message || 'Transaction failed');
      setTimeout(() => setStatus('idle'), 3000);
    }
  };

  const getStatusMessage = () => {
    switch (status) {
      case 'signing': return 'Waiting for signature...';
      case 'pending': return 'Transaction pending...';
      case 'confirmed': return 'Donation successful! 🎉';
      case 'failed': return 'Transaction failed';
      default: return '';
    }
  };

  return (
    <div className="bg-white/90 backdrop-blur-sm rounded-xl border border-gray-200 p-6 space-y-4 hover:shadow-lg transition-all">
      <h3 className="text-xl font-semibold text-gray-900">Make a Donation</h3>

      <div className="bg-gradient-to-br from-emerald-50 to-teal-50 rounded-lg p-4 border border-emerald-200">
        <div className="text-sm text-gray-600 mb-1">Fixed Donation Amount</div>
        {loading ? (
          <div className="text-2xl font-bold text-gray-400">Loading...</div>
        ) : (
          <>
            <div className="text-3xl font-bold text-emerald-600">${requiredUSD} USD</div>
            <div className="text-sm text-gray-500 mt-1">≈ {parseFloat(requiredETH).toFixed(6)} ETH</div>
            <div className="text-xs text-gray-400 mt-2">Price updates every 30 seconds via Chainlink</div>
          </>
        )}
      </div>

      <button
        onClick={handleDonate}
        disabled={!signer || status !== 'idle' || loading}
        className="w-full px-6 py-4 bg-emerald-600 text-white rounded-lg font-bold text-lg hover:bg-emerald-700 transition-all transform hover:scale-105 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 min-h-[44px]"
      >
        {status === 'idle' ? `Donate $${requiredUSD}` : getStatusMessage()}
      </button>

      {txHash && (
        <a
          href={`https://sepolia.etherscan.io/tx/${txHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block text-center text-sm text-emerald-600 hover:text-emerald-700 hover:underline transition-colors"
        >
          View on Etherscan →
        </a>
      )}

      <AnimatePresence>
        {showModal && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.8 }}
            className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4"
            onClick={() => setShowModal(false)}
          >
            <div className="bg-white rounded-2xl p-8 max-w-md text-center">
              <div className="text-6xl mb-4">🎉</div>
              <h3 className="text-2xl font-bold text-gray-800 mb-2">Thank You!</h3>
              <p className="text-gray-600">Your ${requiredUSD} donation has been received successfully</p>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

