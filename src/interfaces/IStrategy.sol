// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import { IDragonTokenizedStrategy } from "./IDragonTokenizedStrategy.sol";
import { IBaseStrategy } from "./IBaseStrategy.sol";
import { ITokenizedStrategy } from "./ITokenizedStrategy.sol";

interface IStrategy is IBaseStrategy, IDragonTokenizedStrategy {}
