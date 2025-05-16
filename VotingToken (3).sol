// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VotingToken is ERC20, Ownable {
    uint256 immutable maxTokens; //cantidad maxima de token que existiran
    
    constructor(string memory name, string memory symbol, uint256 _maxToken, address initialOwner) ERC20(name, symbol) Ownable(initialOwner) {
        // el constructor recibe el nombre y el simbolo del token, la direccion del propietario del contrato y el numero maximo de token que se pueden crear
        require(_maxToken > 0, "El numero maximo debe ser mayor que 0");
        maxTokens = _maxToken;
    }
    
    function mint(address account, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= maxTokens, "No se puede superar el maximo de tokens"); //comprueba que el numero de tokens que hay mas el que se quiere añadir no supere el maximo
        _mint(account, amount); //crea los tokens que hayamos solicitado y le damos la direccion
    }
    
    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount); //elimina los tokens que hayamos solicitado a esa direccion
    }
}