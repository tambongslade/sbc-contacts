import { ApiProperty, ApiPropertyOptional, PartialType } from '@nestjs/swagger';
import { DispatchStatus, RequestStatus, ServiceMode } from '@prisma/client';
import { Type } from 'class-transformer';
import {
  ArrayMaxSize,
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsIn,
  IsInt,
  IsObject,
  IsOptional,
  IsString,
  IsUrl,
  IsUUID,
  Max,
  MaxLength,
  Min,
  MinLength,
  ValidateNested,
} from 'class-validator';
import { PaginationQueryDto } from '../../../common/dto/pagination.dto';

// ── Pro side ────────────────────────────────────────────────────────────────

/** The fields a pro adds on top of the SBC profile (Data §3). */
export class UpsertProProfileDto {
  @ApiProperty({ example: 'Coiffeur' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  profession!: string;

  @ApiProperty({ description: "Présentation libre de l'activité" })
  @IsString()
  @MinLength(10)
  @MaxLength(2000)
  description!: string;

  @ApiProperty({ example: 'Yaoundé' })
  @IsString()
  @MinLength(2)
  @MaxLength(80)
  city!: string;

  @ApiPropertyOptional({ type: [String], description: 'Quartiers, villes ou zones desservies' })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  zones?: string[];

  @ApiProperty({ enum: ServiceMode, isArray: true })
  @IsArray()
  @IsEnum(ServiceMode, { each: true })
  modes!: ServiceMode[];

  @ApiProperty({ example: 'Lun–sam 8h–18h, ou sur rendez-vous' })
  @IsString()
  @MinLength(2)
  @MaxLength(200)
  availability!: string;

  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) priceMin?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) priceMax?: number;

  @ApiProperty({ description: 'Lien de la boutique SBC Shop' })
  @IsUrl({ require_protocol: true, protocols: ['https', 'http'] })
  @MaxLength(500)
  shopUrl!: string;

  @ApiPropertyOptional({ description: 'Numéro WhatsApp, si différent du numéro SBC' })
  @IsOptional()
  @IsString()
  @MaxLength(30)
  whatsapp?: string;
}

export class AssistantMessageDto {
  @ApiProperty({ enum: ['user', 'assistant'] })
  @IsIn(['user', 'assistant'])
  role!: 'user' | 'assistant';

  @ApiProperty()
  @IsString()
  @MaxLength(2000)
  text!: string;
}

/** One turn of the setup conversation: the transcript and the draft so far. */
export class AssistantTurnDto {
  @ApiProperty({ type: [AssistantMessageDto] })
  @IsArray()
  @ArrayMaxSize(60)
  @ValidateNested({ each: true })
  @Type(() => AssistantMessageDto)
  messages!: AssistantMessageDto[];

  @ApiPropertyOptional({ description: 'The draft returned by the previous turn' })
  @IsOptional()
  @IsObject()
  draft?: Record<string, unknown>;
}

export class StructureServicesDto {
  @ApiProperty({ example: 'je fais les dreads, pose de locks, entretien et réparation' })
  @IsString()
  @MinLength(3)
  @MaxLength(1000)
  text!: string;
}

/** A service as accepted (possibly edited) by the pro (Data §4). */
export class ProServiceInputDto {
  @ApiProperty() @IsString() @MinLength(2) @MaxLength(120) name!: string;
  @ApiProperty() @IsString() @MaxLength(120) category!: string;
  @ApiProperty() @IsString() @MaxLength(80) profession!: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  synonyms?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  specialties?: string[];

  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(2000) description?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) priceMin?: number;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) priceMax?: number;

  @ApiPropertyOptional({ enum: ServiceMode, isArray: true })
  @IsOptional()
  @IsArray()
  @IsEnum(ServiceMode, { each: true })
  modes?: ServiceMode[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(30)
  @IsString({ each: true })
  @MaxLength(80, { each: true })
  zones?: string[];

  @ApiPropertyOptional({ example: '24h' }) @IsOptional() @IsString() @MaxLength(60) delay?: string;
}

export class AddServicesDto {
  @ApiProperty({ type: [ProServiceInputDto] })
  @IsArray()
  @ArrayMaxSize(20)
  @ValidateNested({ each: true })
  @Type(() => ProServiceInputDto)
  services!: ProServiceInputDto[];
}

export class UpdateServiceDto extends PartialType(ProServiceInputDto) {
  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
}

export const PRO_ACTIONS = ['INTERESTED', 'QUESTION', 'UNAVAILABLE', 'DECLINED'] as const;
export type ProAction = (typeof PRO_ACTIONS)[number];

/** The four answers a pro can give a request (Data §10). */
export class RespondDto {
  @ApiProperty({ enum: PRO_ACTIONS })
  @IsIn(PRO_ACTIONS)
  action!: ProAction;

  @ApiPropertyOptional({ description: 'Prix proposé (FCFA)' })
  @IsOptional()
  @IsInt()
  @Min(0)
  @Max(100_000_000)
  price?: number;

  @ApiPropertyOptional({ description: 'Créneau proposé — obligatoire si intéressé' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  availability?: string;

  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(60) delay?: string;

  @ApiPropertyOptional({ description: 'Message, ou la question posée' })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  message?: string;
}

export class InboxQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: DispatchStatus })
  @IsOptional()
  @IsEnum(DispatchStatus)
  status?: DispatchStatus;
}

// ── Requester side ──────────────────────────────────────────────────────────

/** "De quoi avez-vous besoin ?" (Data §6). Only the text is required. */
export class CreateRequestDto {
  @ApiProperty({ example: 'Je cherche quelqu’un pour réparer mes locks samedi à Yaoundé' })
  @IsString()
  @MinLength(8)
  @MaxLength(2000)
  text!: string;

  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) city?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) budget?: number;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(60) desiredDate?: string;
  @ApiPropertyOptional({ enum: ServiceMode }) @IsOptional() @IsEnum(ServiceMode) mode?: ServiceMode;
}

/** Corrections to the AI's reading before sending, or an answer to its question. */
export class UpdateRequestDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) profession?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) service?: string;
  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(10)
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  specialties?: string[];
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) city?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) district?: string;
  @ApiPropertyOptional({ enum: ServiceMode }) @IsOptional() @IsEnum(ServiceMode) mode?: ServiceMode;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(60) desiredDate?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(30) desiredTime?: string;
  @ApiPropertyOptional() @IsOptional() @IsInt() @Min(0) budget?: number;

  @ApiPropertyOptional({ description: "Réponse à la question de l'IA — relance l'analyse" })
  @IsOptional()
  @IsString()
  @MaxLength(200)
  clarificationAnswer?: string;
}

export class RequestsQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: RequestStatus })
  @IsOptional()
  @IsEnum(RequestStatus)
  status?: RequestStatus;
}

export class MessageDto {
  @ApiProperty({ example: 'Oui, les locks font environ 30 cm.' })
  @IsString()
  @MinLength(1)
  @MaxLength(1000)
  text!: string;
}

export class RequesterMessageDto extends MessageDto {
  @ApiProperty({ description: 'The pro (dispatch) this message is for' })
  @IsUUID()
  dispatchId!: string;
}

export class SelectProDto {
  @ApiProperty({ description: 'The dispatch (response) being chosen' })
  @IsUUID()
  dispatchId!: string;
}

/** End of the job (Data §15). Stars only count when the job was done. */
export class CompleteRequestDto {
  @ApiProperty({ description: 'La prestation a-t-elle été réalisée ?' })
  @IsBoolean()
  performed!: boolean;

  @ApiPropertyOptional({ minimum: 1, maximum: 5 })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(5)
  stars?: number;

  @ApiPropertyOptional({ description: 'Commentaire, ou description du problème' })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  comment?: string;
}

// ── Admin ───────────────────────────────────────────────────────────────────

export class AdminListQueryDto extends PaginationQueryDto {}

export class AdminProsQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: ['on', 'off'], description: 'Reception active or not' })
  @IsOptional()
  @IsIn(['on', 'off'])
  receiving?: 'on' | 'off';
}

export class AdminRequestsQueryDto extends PaginationQueryDto {
  @ApiPropertyOptional({ enum: RequestStatus })
  @IsOptional()
  @IsEnum(RequestStatus)
  status?: RequestStatus;
}

/** Back-office correction of a service (Data §5, §21). */
export class AdminServiceUpdateDto {
  @ApiPropertyOptional() @IsOptional() @IsString() @MinLength(2) @MaxLength(120) name?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(120) category?: string;
  @ApiPropertyOptional() @IsOptional() @IsString() @MaxLength(80) profession?: string;

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(40)
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  synonyms?: string[];

  @ApiPropertyOptional({ type: [String] })
  @IsOptional()
  @IsArray()
  @ArrayMaxSize(20)
  @IsString({ each: true })
  @MaxLength(60, { each: true })
  specialties?: string[];

  @ApiPropertyOptional() @IsOptional() @IsBoolean() isActive?: boolean;
}

export class MergeServiceDto {
  @ApiProperty({ description: 'The service that absorbs this one' })
  @IsUUID()
  intoId!: string;
}

/** Window + size for the unfulfilled-demand report (Data §E). */
export class UnfulfilledAnalyticsQueryDto {
  @ApiPropertyOptional({ description: 'Début de fenêtre (ISO date); omis = depuis toujours' })
  @IsOptional()
  @IsDateString()
  from?: string;

  @ApiPropertyOptional({ description: 'Fin de fenêtre (ISO date); omis = maintenant' })
  @IsOptional()
  @IsDateString()
  to?: string;

  @ApiPropertyOptional({ description: 'Nombre de termes renvoyés', default: 50 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(200)
  limit = 50;
}

/** Switch request reception on/off until payments exist (Data §17). */
export class SetReceivingDto {
  @ApiProperty() @IsBoolean() enabled!: boolean;

  @ApiPropertyOptional({ description: 'Fin des droits (ISO date); omis = sans limite' })
  @IsOptional()
  @IsDateString()
  until?: string;
}
