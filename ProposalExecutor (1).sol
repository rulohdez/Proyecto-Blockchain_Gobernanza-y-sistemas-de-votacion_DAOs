// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "Proyecto/IExecutableProposal.sol";

contract ProposalExecutor is IExecutableProposal {
    event ProposalExecuted(uint256 proposalId, uint256 votes, uint256 tokens, uint256 amount, uint256 contractBalance);

    function executeProposal(uint256 proposalId, uint256 votes, uint256 tokens) external payable override {
        uint256 amount = msg.value; // Obtener la cantidad de Ether enviada con la llamada
        uint256 contractBalance = address(this).balance;

        emit ProposalExecuted(proposalId, votes, tokens, amount, contractBalance);
    }
}
