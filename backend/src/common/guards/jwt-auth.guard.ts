import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { JwtService } from '@nestjs/jwt';
import { Request } from 'express';
import { IS_PUBLIC_KEY } from '../decorators/public.decorator';
import { AuthenticatedUser } from '../decorators/current-user.decorator';

interface AccessTokenPayload {
  sub: string;
  sbcUserId: string;
  role: AuthenticatedUser['role'];
  type: 'access';
}

/**
 * Global guard: every route requires a valid app access JWT unless marked
 * @Public. Verifies signature + expiry and attaches the principal to req.user.
 */
@Injectable()
export class JwtAuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;

    const request = context.switchToHttp().getRequest<Request>();
    const token = this.extractToken(request);
    if (!token) throw new UnauthorizedException('Missing access token');

    try {
      const payload = await this.jwt.verifyAsync<AccessTokenPayload>(token, {
        secret: this.config.get<string>('jwt.accessSecret'),
      });
      if (payload.type !== 'access') {
        throw new UnauthorizedException('Wrong token type');
      }
      (request as Request & { user: AuthenticatedUser }).user = {
        userId: payload.sub,
        sbcUserId: payload.sbcUserId,
        role: payload.role,
      };
      return true;
    } catch {
      throw new UnauthorizedException('Invalid or expired access token');
    }
  }

  private extractToken(request: Request): string | undefined {
    const auth = request.headers.authorization;
    if (!auth) return undefined;
    const [scheme, value] = auth.split(' ');
    return scheme === 'Bearer' && value ? value : undefined;
  }
}
