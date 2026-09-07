import { SetMetadata } from '@nestjs/common';
import { RAW_RESPONSE } from '../interceptors/response.interceptor';

/** Marks a handler to bypass the standard success envelope (files, health). */
export const Raw = () => SetMetadata(RAW_RESPONSE, true);
