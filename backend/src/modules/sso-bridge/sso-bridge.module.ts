import { Module } from '@nestjs/common';
import { SsoBridgeController } from './sso-bridge.controller';

@Module({
  controllers: [SsoBridgeController],
})
export class SsoBridgeModule {}
