import { Global, Module } from '@nestjs/common';
import { MemberMatchService } from './member-match.service';
import { MembersService } from './members.service';

/** Global: directory, favorites, sync and matching all share the mirror. */
@Global()
@Module({
  providers: [MembersService, MemberMatchService],
  exports: [MembersService, MemberMatchService],
})
export class MembersModule {}
