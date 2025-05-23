// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "Proyecto/VotingToken.sol";
import "Proyecto/IExecutableProposal.sol";

contract QuadraticVoting {
    enum ProposalState { Active, Approved, Cancelled } //activo/aprovado/cancelado

    // Estructuras
    struct Proposal {
        string title; //titulo de la propuesta
        string description; //descripcion de la propuesta
        address proposer; //direccion de la persona que propone
        uint256 budget; //presupuesto para que se de a cabo la propuesta
        address executor;  // Contrato que implementa IExecutableProposal
        uint256 votes; //votos de la propuesta
        uint256 tokens; //token de la propuesta
        bool isSignaling; // true si es una propuesta sde signaling (presupuesto = 0)
        ProposalState state; // Estado actual de la propuesta (Activa, Aprobada, Cancelada)
        uint256 proposalIndex; // Índice en el array correspondiente para acceso rápido
        bool isExecuted; // Indica si la propuesta ya ha sido ejecutada
        mapping(address => Vote) voterInfo; // Registro de votos por cada participante
        address[] voters; // Array para rastrear quién votó (a lo mejor se quita)
    }
    
    struct Vote {
        uint256 votes;
        uint256 tokens; //no haria falta tokens y se podria calcular solo con el numero de votos, es para aclarar el codigo
    }
    
    // Variables de estado
    address immutable owner; //dueño del contrato
    VotingToken public token; //contrato que crea los token
    uint256 immutable precioPorToken; //precio de cada token
    uint256 public presupuestoTotal; //presupuesto total para las propuestas
    uint256 public numProposals; //numero de propuestas creadas (para llevar el recuento de las id)
    bool public votingOpen; //variable que dice si esta abiera o no la votacion
    uint256 public numParticipants; // Número total de participantes en la votación
    
    mapping(address => bool) public participants; //dice si la persona (el address es un participante)
    mapping(uint256 => Proposal) public proposals; //las propuestas con su id
    
    // Arrays para almacenar IDs de propuestas según su estado
    uint256[] public pendingProposalIds;       // Propuestas pendientes (activas con presupuesto)
    uint256[] public approvedProposalIds;      // Propuestas aprobadas
    uint256[] public signalingProposalIds;     // Propuestas de señalización (sin presupuesto)
    uint256[] public cancelledProposalIds;     // Propuestas canceladas (realmente podria no estar porque no afecta a la logica pero por una futura amplicacion o si se quiere hacer una auditoria de las propuestas canceladas pues si, puesto que no se deberia de borrar datos nunca)
    
    // Eventos
    event VotingOpened(uint256 budget, address owner); 
    event VotingClosed();
    event ProposalAdded(uint256 id, string title, uint256 budget, bool isSignaling);
    event ProposalCancelled(uint256 id);
    event ProposalApproved(uint256 id, uint256 budget);
    event TokensBought(address buyer, uint256 amount);
    event TokensSold(address seller, uint256 amount);
    event VotesStaked(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    event VotesWithdrawn(address voter, uint256 proposalId, uint256 votes, uint256 tokens);
    event ParticipantAdded(address participante, uint256 tokensComprados, uint256 etherEnviado); // Cuando se registra un participante
    event ParticipantRemove(address participante); // Cuando un participante se da de baja
    event TokensRefunded(address voter, uint256 amount);
    event ProposalExecuted(uint256 proposalId);  // Evento para cuando se ejecuta una propuesta
    event TokensRefundedFromProposal(address participante, uint256 propuesta, uint256 cantidad);

    // Modificadores
    modifier onlyOwner() { //comprueba que es el propietario del contrato
        require(msg.sender == owner, "Solo el propietario puede ejecutar esta funcion");
        _;
    }
    
    modifier onlyParticipant() { //comprueba que es participante
        require(participants[msg.sender], "Solo los participantes pueden ejecutar esta funcion");
        _;
    }
    
    modifier votingIsOpen() { //comprueba que la votacion este abierta
        require(votingOpen, "El periodo de votacion no esta abierto");
        _;
    }

    constructor(uint _precioToken, uint _maxTokens) {
        require(_precioToken > 0 && _maxTokens > 0, "Los valores tienen que ser mayores que 0"); 
        owner = msg.sender; //guarda el dueño del contrato (habrá funciones que solo puede hacer el)
        precioPorToken = _precioToken; //inicializa el precio por cada token
        
        token = new VotingToken("Voting Token", "VOTE", _maxTokens, address(this)); // Crear el contrato de tokens
        votingOpen = false; //inicializa que todavia no se ha abierto la votacion
    }

    function openVoting() external payable onlyOwner { //solo lo puede ejecutar el dueño del contrato y es para comenzar la votacion con su presupuesto inicial
        require(!votingOpen, "La votacion ya esta abierta"); //comprueba que la votacion no ha sido iniciada
        require(msg.value > 0, "El presupuesto inicial debe ser mayor que 0"); //comprueba que el presupuesto inicial es mayor que 0

        votingOpen = true; //cambia la variable para que marque que ahora si esta abierta la votacion
        presupuestoTotal = msg.value; //inicializa el presupuesto total de la propuesta a la inical (puede aumentar y disminuir dependiendo de las propuestas)
        // Limpiar arrays de propuestas de la votación anterior (si existe)
        delete pendingProposalIds;
        delete approvedProposalIds;
        delete signalingProposalIds;
        delete cancelledProposalIds;
        
        emit VotingOpened(presupuestoTotal, owner); //hace el evento indicando el presupuesto inicial de la propuesta y el dueño que es tambien el del contrato
    }

    function addParticipant() external payable { //añade un participante 
        require(!participants[msg.sender], "Ya eres un participante");
        require(msg.value >= precioPorToken, "Debes comprar al menos un token");
        
        uint256 tokenAmount = msg.value / precioPorToken; //commprueba cuentos token puede comprar
                
        token.mint(msg.sender, tokenAmount); // Crear tokens para el participante

        participants[msg.sender] = true;  // Registrar participante
        numParticipants++; //aumenta el numero de participante

        uint256 etherADevolver = msg.value - (tokenAmount * precioPorToken);
        if (etherADevolver > 0) {
            (bool success, ) = msg.sender.call{value: etherADevolver}("");
            require(success, "Error al reembolsar el Ether");
        }
        
        emit ParticipantAdded(msg.sender, tokenAmount, tokenAmount * precioPorToken); 
        emit TokensBought(msg.sender, tokenAmount);
    }
    
    function removeParticipant() external onlyParticipant { //comprueba que solo lo puede ejecutar un participante y es para eliminar un participante
        participants[msg.sender] = false; //pone que el participante ya no lo es
        numParticipants--; //lo resta del numero de participantes
        
        emit ParticipantRemove(msg.sender);
    }

    function addProposal(string calldata title, string calldata description, uint256 budget, address executor) external votingIsOpen onlyParticipant returns (uint256) {
        require(bytes(title).length > 0, "El titulo no puede ser vacio");
        require(bytes(description).length > 0, "La descripcion no puede ser vacia");
        require(executor != address(0), "Direccion de ejecutor invalida"); //comprobamos que la dirección del ejecutor no sea la dirección cero (address(0))
        
        uint256 proposalId = numProposals++;  // Se asigna un ID único a la propuesta incrementando el contador numProposals
        Proposal storage newProposal = proposals[proposalId]; //Se crea una nueva entrada en el mapping proposals con ese ID

        newProposal.title = title;
        newProposal.description = description;
        newProposal.proposer = msg.sender;
        newProposal.budget = budget;
        newProposal.executor = executor;
        newProposal.votes = 0;
        newProposal.tokens = 0;
        newProposal.state = ProposalState.Active;
        newProposal.isSignaling = (budget == 0);        
    
        if (newProposal.isSignaling) {// Si es una propuesta de signaling (presupuesto = 0), se añade a la lista signalingProposalIds
            newProposal.proposalIndex = signalingProposalIds.length; //guardamos el indice
            signalingProposalIds.push(proposalId);
        } else {// Si es una propuesta de financiación (presupuesto > 0), se añade a la lista pendingProposalIds
            newProposal.proposalIndex = pendingProposalIds.length;
            pendingProposalIds.push(proposalId);
        }
        
        emit ProposalAdded(proposalId, title, budget, newProposal.isSignaling);
        
        return proposalId;
    }
    
    function cancelProposal(uint256 proposalId) external votingIsOpen {
        Proposal storage proposal = proposals[proposalId];
        
        require(proposal.proposer == msg.sender, "Solo el creador puede cancelar la propuesta");
        require(proposal.state == ProposalState.Active, "La propuesta no esta activa");
        
        proposal.state = ProposalState.Cancelled;// Marcar como cancelada
        
        uint256 indexToRemove = proposal.proposalIndex; // Obtener el índice del elemento en la lista de propuesta
        uint256[] storage sourceArray;
        
        if (proposal.isSignaling) { //comprueba si es Signaling
            sourceArray = signalingProposalIds;
        } else {
            sourceArray = pendingProposalIds;
        }
        
        if (sourceArray.length > 0 && indexToRemove < sourceArray.length) {//  si hay elementos en el array y el índice es válido
            uint256 lastProposalId = sourceArray[sourceArray.length - 1];  // Obtenemos el último elemento del array
            
            if (proposalId != lastProposalId) {
                sourceArray[indexToRemove] = lastProposalId;// Mover el último elemento al lugar del eliminado
                proposals[lastProposalId].proposalIndex = indexToRemove;// Actualizar el índice en el elemento movido
            }
            
            sourceArray.pop(); // Eliminar el último elemento
        }
        
        proposal.proposalIndex = cancelledProposalIds.length;
        cancelledProposalIds.push(proposalId); // Añadir a la lista de canceladas
               
        emit ProposalCancelled(proposalId);
    }

    function buyTokens() external payable onlyParticipant {
        require(msg.value >= precioPorToken, "Debes enviar suficiente ETH para comprar al menos un token");
        
        uint256 numTokens = msg.value / precioPorToken;
        
        // Crear tokens para el participante
        token.mint(msg.sender, numTokens);

        uint256 etherADevolver = msg.value - (numTokens * precioPorToken);
        if (etherADevolver > 0) {
            (bool success, ) = msg.sender.call{value: etherADevolver}("");
            require(success, "Error al reembolsar el Ether");
        }
        
        emit TokensBought(msg.sender, numTokens);
    }

    function sellTokens(uint256 amount) external onlyParticipant {
        require(amount > 0, "La cantidad debe ser mayor que cero");
        require(token.balanceOf(msg.sender) >= amount, "No tienes suficientes tokens para vender");
        
        uint256 ethAmount = amount * precioPorToken;
        
        // Transferir tokens al contrato y quemarlos
        token.transfer(address(this), amount); // El participante transfiere sus tokens al contrato
        token.burn(address(this), amount);
        
        // Transferir ETH al vendedor
        (bool success, ) = msg.sender.call{value: ethAmount}("");
        require(success, "Error al enviar ETH");
        
        emit TokensSold(msg.sender, amount);
    }

    function getERC20() external view returns (address) {
        return address(token);
    }
    
    function getPendingProposals() external view votingIsOpen returns (uint256[] memory) {
        return pendingProposalIds;
    }
    
    function getApprovedProposals() external view votingIsOpen returns (uint256[] memory) {
        return approvedProposalIds;
    }    
    
    function getSignalingProposals() external view votingIsOpen returns (uint256[] memory) {
        return signalingProposalIds;
    }    
   
    function getCancelledProposals() external view returns (uint256[] memory) {
        return cancelledProposalIds;
    }

    function getProposalInfo(uint256 proposalId) external view votingIsOpen returns (
        string memory title,
        string memory description,
        address proposer,
        uint256 budget,
        address executor,
        uint256 _votes,
        uint256 tokens,
        ProposalState state,
        bool isSignaling,
        bool isExecuted
    ) {
        Proposal storage proposal = proposals[proposalId];
        
        return (
            proposal.title,
            proposal.description,
            proposal.proposer,
            proposal.budget,
            proposal.executor,
            proposal.votes,
            proposal.tokens,
            proposal.state,
            proposal.isSignaling,
            proposal.isExecuted
        );
    }

    function stake(uint256 proposalId, uint256 votesAmount) external votingIsOpen onlyParticipant {
        require(proposals[proposalId].state == ProposalState.Active, "La propuesta no esta activa");
        require(votesAmount > 0, "Debes depositar al menos un voto");

        Proposal storage proposal = proposals[proposalId]; //coge la propuesta
        Vote storage voterVoteInfo = proposal.voterInfo[msg.sender]; //coge la informacion del voto del participante (participant) de la propuesta
        uint256 currentVotes = voterVoteInfo.votes; //coge los votos actuales que ha puesto el participante en la propuesta

        // Calcular los tokens necesarios para los votos adicionales (costo cuadratico)
        uint256 tokensNeeded = (currentVotes + votesAmount) * (currentVotes + votesAmount) - (currentVotes * currentVotes);

        require(token.allowance(msg.sender, address(this)) >= tokensNeeded, "Debes aprobar al contrato para transferir los tokens necesarios");
        require(token.balanceOf(msg.sender) >= tokensNeeded, "No tienes suficientes tokens para depositar estos votos");

        // Transferir los tokens desde el votante al contrato
        token.transferFrom(msg.sender, address(this), tokensNeeded);

        proposal.votes += votesAmount; //le suma a la propuesta el numero de votos
        proposal.tokens += tokensNeeded; //le suma a la propuesta el numero de tokens
        voterVoteInfo.votes += votesAmount; //suma los votos del participante en la propuesta
        voterVoteInfo.tokens += tokensNeeded; //suma los tokens del participante en la propuesta

        // Añadir al array de votantes si no ha votado antes
        if (voterVoteInfo.votes == votesAmount) { // Si es la primera vez que vota
            proposal.voters.push(msg.sender);
        }

         // Comprobar si se puede ejecutar la propuesta (solo para propuestas de financiación)
        if (!proposal.isSignaling) {
            _checkAndExecuteProposal(proposalId);
        }

        emit VotesStaked(msg.sender, proposalId, votesAmount, tokensNeeded);
    }

    function withdrawFromProposal(uint256 proposalId, uint256 votesAmount) external votingIsOpen onlyParticipant {
        Proposal storage proposal = proposals[proposalId];
        Vote storage voterVoteInfo = proposal.voterInfo[msg.sender];

        require(proposal.state == ProposalState.Active, "La propuesta no esta activa");
        require(votesAmount > 0, "Debes retirar al menos un voto");
        require(voterVoteInfo.votes >= votesAmount, "No tienes suficientes votos depositados en esta propuesta");

        uint256 currentVotes = voterVoteInfo.votes; //guarda los votos que el participante ha puesto en la propuesta
        uint256 tokensToReturn = (currentVotes * currentVotes) - ((currentVotes - votesAmount) * (currentVotes - votesAmount)); //calcula los tokens que le tienen que devolver

        // Transferir los tokens al votante
        (bool success) = token.transfer(msg.sender, tokensToReturn);
        require(success, "Error al transferir los tokens");

        proposal.votes -= votesAmount; //le resta los votos a la propuesta
        proposal.tokens -= tokensToReturn; //le resta los tokens a la propuesta

        voterVoteInfo.votes -= votesAmount; //le resta los votos del participante en la propuesta
        voterVoteInfo.tokens -= tokensToReturn; //le resta los tokens del participante en la propuesta

        emit VotesWithdrawn(msg.sender, proposalId, votesAmount, tokensToReturn);
    }

    function _checkAndExecuteProposal(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];

        //comprueba que sea activo, que no es signaling, que el numero de votos es mayor que 0 y que este no haya sido ejecutada ya 
        if (proposal.state == ProposalState.Active && !proposal.isSignaling && proposal.votes > 0 && !proposal.isExecuted) {
            
            // Calcular el umbral para aprobar la propuesta
            uint256 threshold = _calculateThreshold(proposalId);
            
            // Comprobar si se cumplen las condiciones para aprobar la propuesta
            if (proposal.votes >= threshold && presupuestoTotal >= proposal.budget) {

                proposal.state = ProposalState.Approved; // Cambiar el estado a Aprobado
                proposal.isExecuted = true; //pone que ha sido ejecutado

                presupuestoTotal = presupuestoTotal - proposal.budget + proposal.tokens*precioPorToken; // Actualizar el presupuesto total
                token.burn(address(this), proposal.tokens); // Eliminar los tokens asociados a los votos (quemarlos desde el contrato)

                // Actualizar arrays de estado
                // Eliminar de pendingProposalIds
                uint256 indexToRemove = proposal.proposalIndex;
                if (pendingProposalIds.length > 0 && indexToRemove < pendingProposalIds.length) {
                    uint256 lastProposalId = pendingProposalIds[pendingProposalIds.length - 1];
                    if (proposalId != lastProposalId) {
                        pendingProposalIds[indexToRemove] = lastProposalId;
                        proposals[lastProposalId].proposalIndex = indexToRemove;
                    }
                    pendingProposalIds.pop();
                }

                // Añadir a approvedProposalIds
                proposal.proposalIndex = approvedProposalIds.length;
                approvedProposalIds.push(proposalId);

                // Llamar a la función executeProposal del contrato externo
                IExecutableProposal(proposal.executor).executeProposal{value: proposal.budget}(proposalId, proposal.votes, proposal.tokens);

                emit ProposalApproved(proposalId, proposal.budget);
            }
        }
    }

    // Calcular el umbral para aprobar una propuesta
    function _calculateThreshold(uint256 proposalId) internal view returns (uint256) {
        Proposal storage proposal = proposals[proposalId];
        
        uint256 pendingProposalsCount = pendingProposalIds.length; //Esto lo podriamos poner directamente en la formula pero por claridad mejor aqui
        
        return uint256(
            (2 * 1e17 + (proposal.budget * 1e18) / presupuestoTotal) * numParticipants / 1e18 + pendingProposalsCount
        );
    }

    function closeVoting() external onlyOwner votingIsOpen {
        votingOpen = false; 

        // Devolver el presupuesto restante al propietario
        if (presupuestoTotal > 0) {
            (bool success, ) = owner.call{value: presupuestoTotal}("");
            require(success, "Error al transferir el presupuesto restante");
        }
        presupuestoTotal = 0;

        emit VotingClosed();
    }

    function _executeSignalingProposal(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(!votingOpen, "Debe cerrarse la votacion");
        require(proposal.isSignaling, "La propuesta no es de signaling");
        require(!proposal.isExecuted, "La propuesta ya ha sido ejecutada");

        // Eliminar de Singaling
        uint256 indexToRemove = proposal.proposalIndex;
        if (signalingProposalIds.length > 0 && indexToRemove < signalingProposalIds.length) {
            uint256 lastProposalId = signalingProposalIds[signalingProposalIds.length - 1];
            if (proposalId != lastProposalId) {
                signalingProposalIds[indexToRemove] = lastProposalId;
                proposals[lastProposalId].proposalIndex = indexToRemove;
            }
            signalingProposalIds.pop();
        }

        proposal.isExecuted = true;
        IExecutableProposal(proposal.executor).executeProposal{value: proposal.budget}(proposalId, proposal.votes, proposal.tokens);
        emit ProposalExecuted(proposalId);
    }

    function claimRefundFromProposal(uint256 proposalId) external onlyParticipant {
        Proposal storage proposal = proposals[proposalId];
        Vote storage vote = proposal.voterInfo[msg.sender];
        
        require(vote.votes > 0, "No tienes votos en esta propuesta");
        require(vote.tokens > 0, "Ya has retirado tus tokens");
        require(proposal.state == ProposalState.Cancelled || (proposal.isExecuted && proposal.isSignaling), "Solo se pueden retirar tokens de propuestas canceladas o ya signaling aprobadas");
        
        uint256 tokenDevolver = vote.tokens;
        
        // Marcar tokens como retirados
        vote.tokens = 0;
        
        // Transferir tokens al votante
        token.transfer(msg.sender, tokenDevolver);
        
        emit TokensRefundedFromProposal(msg.sender, proposalId, tokenDevolver);
    }

}
