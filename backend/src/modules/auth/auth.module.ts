import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { RolesGuard } from '../../common/guards/roles.guard';
import { AuthController } from './controllers/auth.controller';
import { AuthService } from './services/auth.service';
import { SbcTokenService } from './services/sbc-token.service';
import { TokenService } from './services/token.service';

@Module({
  imports: [JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    TokenService,
    SbcTokenService,
    // Registered here (order matters): authenticate, then authorize. Both are
    // global — every route is protected by default unless marked @Public.
    { provide: APP_GUARD, useClass: JwtAuthGuard },
    { provide: APP_GUARD, useClass: RolesGuard },
  ],
  // SbcTokenService is consumed by the directory/sync modules in later phases.
  exports: [SbcTokenService, TokenService],
})
export class AuthModule {}
