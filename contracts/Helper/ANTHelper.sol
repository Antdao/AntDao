pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "../Access/ANTAccessControls.sol";



interface IUniswapFactory {
    function getPair(address token0, address token1) external view returns (address);
}

interface IUniswapPair {
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner) external view returns (uint);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
}


interface IDocument {
    function getDocument(string calldata _name) external view returns (string memory, uint256);
    function getDocumentCount() external view returns (uint256);
    function getDocumentName(uint256 index) external view returns (string memory);    
}

contract DocumentHepler {
    struct Document {
        string name;
        string data;
        uint256 lastModified;
    }

    function getDocuments(address _document) public view returns(Document[] memory) {
        IDocument document = IDocument(_document);
        uint256 documentCount = document.getDocumentCount();

        Document[] memory documents = new Document[](documentCount);

        for(uint256 i = 0; i < documentCount; i++) {
            string memory documentName = document.getDocumentName(i);
            (
                documents[i].data,
                documents[i].lastModified
            ) = document.getDocument(documentName);
            documents[i].name = documentName;
        }
        return documents;
    }
}



interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IAntTokenFactory {
    function getTokens() external view returns (address[] memory);
    function tokens(uint256) external view returns (address);
    function numberOfTokens() external view returns (uint256);
} 

contract TokenHelper {
    struct TokenInfo {
        address addr;
        uint256 decimals;
        string name;
        string symbol;
    }

    function getTokensInfo(address[] memory addresses) public view returns (TokenInfo[] memory)
    {
        TokenInfo[] memory infos = new TokenInfo[](addresses.length);

        for (uint256 i = 0; i < addresses.length; i++) {
            infos[i] = getTokenInfo(addresses[i]);
        }

        return infos;
    }

    function getTokenInfo(address _address) public view returns (TokenInfo memory) {
        TokenInfo memory info;
        IERC20 token = IERC20(_address);

        info.addr = _address;
        info.name = token.name();
        info.symbol = token.symbol();
        info.decimals = token.decimals();

        return info;
    }
     function allowance(address _token, address _owner, address _spender) public view returns(uint256) {
        return IERC20(_token).allowance(_owner, _spender);
    }
}




contract BaseHelper {
    IAntMarketFactory public market;
    IAntTokenFactory public tokenFactory;
    IAntFarmFactory public farmFactory;
    address public launcher;

    ANTAccessControls public accessControls;

    function setContracts(
        address _tokenFactory,
        address _market,
        address _launcher,
        address _farmFactory
    ) public {
        require(
            accessControls.hasAdminRole(msg.sender),
            "ANTHelper: Sender must be Admin"
        );
        if (_market != address(0)) {
            market = IAntMarketFactory(_market);
        }
        if (_tokenFactory != address(0)) {
            tokenFactory = IAntTokenFactory(_tokenFactory);
        }
        if (_launcher != address(0)) {
            launcher = _launcher;
        }
        if (_farmFactory != address(0)) {
            farmFactory = IAntFarmFactory(_farmFactory);
        }
    }
}



interface IAntFarmFactory {
    function getTemplateId(address _farm) external view returns(uint256);
    function numberOfFarms() external view returns(uint256);
    function farms(uint256 _farmId) external view returns(address);
}

interface IFarm {
    function poolInfo(uint256 pid) external view returns(
        address lpToken,
        uint256 allocPoint,
        uint256 lastRewardBlock,
        uint256 accRewardsPerShare
    );
    function rewards() external view returns(address);
    function poolLength() external view returns (uint256);
    function rewardsPerBlock() external view returns (uint256);
    function bonusMultiplier() external view returns (uint256);
    function userInfo(uint256 pid, address _user) external view returns (uint256, uint256);
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256);
}

contract FarmHelper is BaseHelper, TokenHelper {
    struct FarmInfo {
        address addr;
        uint256 templateId;
        uint256 rewardsPerBlock;
        uint256 bonusMultiplier;
        TokenInfo rewardToken;
        PoolInfo[] pools;
    }

    struct PoolInfo {
        address lpToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardsPerShare;
        uint256 totalStaked;
        TokenInfo stakingToken;
    }

    struct UserPoolInfo {
        address farm;
        uint256 pid;
        uint256 totalStaked;
        uint256 lpBalance;
        uint256 lpAllowance;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    struct UserPoolsInfo {
        address farm;
        uint256[] pids;
        uint256[] totalStaked;
        uint256[] pendingRewards;
    }

    function getPools(address _farm) public view returns(PoolInfo[] memory) {
        IFarm farm = IFarm(_farm);
        uint256 poolLength = farm.poolLength();
        PoolInfo[] memory pools = new PoolInfo[](poolLength);
        
        for(uint256 i = 0; i < poolLength; i++) {
            (
                pools[i].lpToken,
                pools[i].allocPoint,
                pools[i].lastRewardBlock,
                pools[i].accRewardsPerShare
            ) = farm.poolInfo(i);
            pools[i].totalStaked = IERC20(pools[i].lpToken).balanceOf(_farm);
            pools[i].stakingToken = getTokenInfo(pools[i].lpToken);
        }
        return pools;
    }


    function getFarms() public view returns(FarmInfo[] memory) {
        uint256 numberOfFarms = farmFactory.numberOfFarms();

        FarmInfo[] memory infos = new FarmInfo[](numberOfFarms);

        for (uint256 i = 0; i < numberOfFarms; i++) {
            address farmAddr = farmFactory.farms(i);
            uint256 templateId = farmFactory.getTemplateId(farmAddr);
            infos[i] = _farmInfo(farmAddr);
        }

        return infos;
    }

    function getFarms(
        uint256 pageSize,
        uint256 pageNbr,
        uint256 offset
    ) public view returns(FarmInfo[] memory) {
        uint256 numberOfFarms = farmFactory.numberOfFarms();
        uint256 startIdx = (pageNbr * pageSize) + offset;
        uint256 endIdx = startIdx + pageSize;

        FarmInfo[] memory infos;

        if (endIdx > numberOfFarms) {
            endIdx = numberOfFarms;
        }
        if(endIdx < startIdx) {
            return infos;
        }
        infos = new FarmInfo[](endIdx - startIdx);

        for (uint256 farmIdx = 0; farmIdx + startIdx < endIdx; farmIdx++) {
            address farmAddr = farmFactory.farms(farmIdx + startIdx);
            infos[farmIdx] = _farmInfo(farmAddr);
        }

        return infos;
    }

    function getFarms(
        uint256 pageSize,
        uint256 pageNbr
    ) public view returns(FarmInfo[] memory) {
        return getFarms(pageSize, pageNbr, 0);
    }

    function _farmInfo(address _farmAddr) private view returns(FarmInfo memory farmInfo) {
            IFarm farm = IFarm(_farmAddr);

            farmInfo.addr = _farmAddr;
            farmInfo.templateId = farmFactory.getTemplateId(_farmAddr);
            farmInfo.rewardsPerBlock = farm.rewardsPerBlock();
            farmInfo.bonusMultiplier = farm.bonusMultiplier();
            farmInfo.rewardToken = getTokenInfo(farm.rewards());
            farmInfo.pools = getPools(_farmAddr);
    }

    function getFarmDetail(address _farm, address _user)  public view returns(FarmInfo memory farmInfo, UserPoolInfo[] memory userInfos) {
        IFarm farm = IFarm(_farm);
        farmInfo.addr = _farm;
        farmInfo.templateId = farmFactory.getTemplateId(_farm);
        farmInfo.rewardsPerBlock = farm.rewardsPerBlock();
        farmInfo.bonusMultiplier = farm.bonusMultiplier();
        farmInfo.rewardToken = getTokenInfo(farm.rewards());
        farmInfo.pools = getPools(_farm);

        if(_user != address(0)) {
            PoolInfo[] memory pools = farmInfo.pools;
            userInfos = new UserPoolInfo[](pools.length);
            for(uint i = 0; i < pools.length; i++) {
                UserPoolInfo memory userInfo = userInfos[i];
                address stakingToken = pools[i].stakingToken.addr;
                (userInfo.totalStaked, userInfo.rewardDebt) = farm.userInfo(i, _user);
                userInfo.lpBalance = IERC20(stakingToken).balanceOf(_user);
                userInfo.lpAllowance = IERC20(stakingToken).allowance(_user, _farm);
                userInfo.pendingRewards = farm.pendingRewards(i, _user);
                (userInfo.totalStaked,) = farm.userInfo(i, _user);
                userInfo.farm = _farm;
                userInfo.pid = i;
                userInfos[i] = userInfo;
            }
        }
        return (farmInfo, userInfos);
    }

    function getUserPoolsInfos(address _user) public view returns(UserPoolsInfo[] memory) {
        uint256 numberOfFarms = farmFactory.numberOfFarms();

        UserPoolsInfo[] memory infos = new UserPoolsInfo[](numberOfFarms);

        for (uint256 i = 0; i < numberOfFarms; i++) {
            address farmAddr = farmFactory.farms(i);
            IFarm farm = IFarm(farmAddr);
            uint256 poolLength = farm.poolLength();
            uint256[] memory totalStaked = new uint256[](poolLength);
            uint256[] memory pendingRewards = new uint256[](poolLength);
            uint256[] memory pids = new uint256[](poolLength);

            for(uint256 j = 0; j < poolLength; j++) {
                (address stakingToken,,,) = farm.poolInfo(j);
                (totalStaked[j],) = farm.userInfo(j, _user);
                pendingRewards[j] = farm.pendingRewards(j, _user);
                pids[j] = j;
            }
            infos[i].totalStaked = totalStaked;
            infos[i].pendingRewards = pendingRewards;
            infos[i].pids = pids;
            infos[i].farm = farmAddr;
        }
        return infos;
    }
}



